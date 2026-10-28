"""Per-user preferences and SSH transport; opted-in passwords use Keychain only."""
import copy
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import select
import signal
import socket
import subprocess
import sys
import tempfile
import time
import importlib.util

_vault_spec = importlib.util.spec_from_file_location('hd2fx_keychain', Path(__file__).with_name('keychain_store.py'))
keychain = importlib.util.module_from_spec(_vault_spec)
_vault_spec.loader.exec_module(keychain)
VAULT = keychain.Keychain()

_locale_spec = importlib.util.spec_from_file_location('hd2fx_pref_locales', Path(__file__).with_name('i18n.py'))
i18n = importlib.util.module_from_spec(_locale_spec)
_locale_spec.loader.exec_module(i18n)

DEFAULTS = {
    'version': 1,
    'ssh': {'host': '127.0.0.1', 'port': 2222, 'username': 'steamos',
            'auth': 'password', 'identity_file': '', 'cdp_local_port': 18094,
            'remember_password': False},
    'appearance': {'emblem': 'current', 'intro_animation': True,
                   'layout': 'immersive', 'language': None},
    'ssh_configured': False,
}


class AuthenticationError(RuntimeError):
    pass


def path():
    override = os.environ.get('HD2FX_SETTINGS_FILE')
    return Path(override).expanduser() if override else Path.home()/'Library/Application Support/Helldivers2FXLauncher/settings.json'


def validate(data):
    if not isinstance(data, dict) or data.get('version') != 1:
        raise ValueError('Unsupported launcher settings format.')
    if not isinstance(data.get('ssh'), dict):
        raise ValueError('Invalid SSH settings.')
    ssh = dict(DEFAULTS['ssh'], **data['ssh'])
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.:%-]*', ssh.get('host', '')):
        raise ValueError('Invalid SSH host. Enter an address without a username or spaces.')
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]*\$?', ssh.get('username', '')):
        raise ValueError('Invalid SSH username.')
    for key in ['port', 'cdp_local_port']:
        value = ssh.get(key)
        if type(value) is not int or not 1 <= value <= 65535:
            raise ValueError('Ports must be numbers between 1 and 65535.')
    if ssh['port'] == ssh['cdp_local_port']:
        raise ValueError('SSH and local Steam interface ports must be different.')
    if ssh.get('auth') not in ['password', 'key']:
        raise ValueError('Select password or SSH key authentication.')
    if type(ssh['remember_password']) is not bool:
        raise ValueError('Invalid save-password setting.')
    if not isinstance(ssh.get('identity_file'), str) or '\n' in ssh['identity_file']:
        raise ValueError('Invalid SSH key path.')
    if data.get('appearance', {}).get('emblem') not in ['current', '1', '2', '3', '4']:
        raise ValueError('Invalid emblem selection.')
    intro = data['appearance'].get('intro_animation', True)
    if type(intro) is not bool:
        raise ValueError('Invalid startup animation setting.')
    layout = data['appearance'].get('layout', 'immersive')
    language = i18n.normalize(data['appearance'].get('language'), strict=True)
    if layout not in ['immersive', 'compact']:
        raise ValueError('Invalid layout setting.')
    if language is not None and language not in i18n.CODES:
        raise ValueError('Invalid language setting.')
    # Keep only known non-secret fields, even when reading a hand-edited file.
    if type(data.get('ssh_configured', False)) is not bool:
        raise ValueError('Invalid SSH setup state.')
    return {'version': 1, 'ssh': {k: ssh[k] for k in DEFAULTS['ssh']},
            'ssh_configured': data.get('ssh_configured', False),
            'appearance': {'emblem': data['appearance']['emblem'], 'intro_animation': intro,
                           'layout': layout, 'language': language}}


def load():
    target = path()
    if not target.exists():
        return copy.deepcopy(DEFAULTS)
    try:
        return validate(json.loads(target.read_text(encoding='utf-8')))
    except (ValueError, KeyError, TypeError) as error:
        raise ValueError('Cannot read launcher settings. Check settings.json: '+str(error)) from error


def save(data):
    data = validate(data)
    target = path()
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix='.settings-', dir=str(target.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.chmod(temporary, 0o600)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def secret(prompt):
    if not sys.stdin.isatty():
        raise AuthenticationError('A password is required. Run the launcher in an interactive terminal.')
    return getpass.getpass(prompt)


def local_host(host):
    return host in ['127.0.0.1', 'localhost', '::1']


class SSHClient:
    def __init__(self, settings, test=False):
        self.settings = validate(settings)['ssh']
        encoded = json.dumps({k:v for k,v in self.settings.items() if k!='remember_password'}, sort_keys=True).encode()
        suffix = hashlib.sha256(encoded).hexdigest()[:14]
        self.socket = '/tmp/hd2fx-'+str(os.getuid())+'-'+suffix+'.sock'
        s = self.settings
        legacy = '/tmp/steamos-hd2-ntsync.sock'
        if not test and s['host'] == '127.0.0.1' and s['port'] == 2222 and s['username'] == 'steamos' and s['cdp_local_port'] == 18094 and Path(legacy).exists():
            self.socket = legacy
        if test:
            self.socket = '/tmp/hd2fx-test-'+str(os.getpid())+'-'+str(time.time_ns())[-10:]+'.sock'
        self.test = test
        self.password = None
        self.prompt_secret = secret
        self.notify = print

    def _saved_password(self):
        if not self.settings['remember_password'] or self.settings['auth'] != 'password':
            return None
        try:
            return VAULT.get(self.settings)
        except keychain.KeychainError:
            self.notify('Keychain password could not be read. Please enter it manually.')
            return None

    def _remember_authenticated_password(self):
        if self.settings['remember_password'] and self.password is not None:
            try:
                VAULT.put(self.settings, self.password)
            except keychain.KeychainError:
                self.notify('SSH connected, but the password could not be saved in Keychain.')

    def base(self):
        s = self.settings
        args = ['ssh', '-S', self.socket, '-p', str(s['port']), '-l', s['username'],
                '-o', 'ConnectTimeout=8', '-o', 'StrictHostKeyChecking=accept-new',
                '-o', 'NumberOfPasswordPrompts=1']
        if s['auth'] == 'key':
            args += ['-o', 'PreferredAuthentications=publickey']
            if s['identity_file']:
                key = Path(s['identity_file']).expanduser()
                if not key.is_file():
                    raise AuthenticationError('The selected SSH private key does not exist.')
                args += ['-i', str(key), '-o', 'IdentitiesOnly=yes']
        else:
            args += ['-o', 'PreferredAuthentications=password,keyboard-interactive']
        return args

    def command(self):
        return self.base()+['-o', 'BatchMode=yes', self.settings['host']]

    def reachable(self):
        try:
            with socket.create_connection((self.settings['host'], self.settings['port']), timeout=.7):
                return True
        except OSError:
            return False

    def connect_once(self):
        base = self.base()
        check = subprocess.run(base+['-O', 'check', self.settings['host']], capture_output=True, timeout=10)
        if check.returncode == 0:
            return
        args = base+['-M', '-N', '-f', '-o', 'ControlMaster=yes',
                     '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=5',
                     '-o', 'ServerAliveCountMax=3']
        if not self.test:
            args += ['-L', '127.0.0.1:'+str(self.settings['cdp_local_port'])+':127.0.0.1:8080']
        args += [self.settings['host']]
        pid, fd = os.forkpty()
        if pid == 0:
            os.execvp(args[0], args)
        buffer = b''
        sent = False
        reaped = False
        deadline = time.monotonic()+25
        try:
            while time.monotonic() < deadline:
                done, status = os.waitpid(pid, os.WNOHANG)
                if done:
                    reaped = True
                    if os.waitstatus_to_exitcode(status) == 0:
                        if sent:
                            self._remember_authenticated_password()
                        return
                    lower = buffer.lower()
                    if b'host identification has changed' in lower:
                        raise AuthenticationError('SSH host key changed. Verify the target before updating known_hosts.')
                    if sent or b'permission denied' in lower:
                        self.password = None
                        raise AuthenticationError('SSH authentication failed. Check the username, password or key in SSH settings.')
                    if b'address already in use' in lower or b'cannot listen to port' in lower:
                        raise AuthenticationError('The local Steam interface port is busy. Change it in SSH settings.')
                    raise RuntimeError('SSH connection is not ready.')
                ready, _, _ = select.select([fd], [], [], .2)
                if not ready:
                    continue
                try:
                    chunk = os.read(fd, 4096)
                except OSError:
                    chunk = b''
                buffer = (buffer+chunk)[-8192:]
                lower = buffer.lower()
                if not sent and (b'password:' in lower or b'passphrase for key' in lower):
                    is_key = b'passphrase for key' in lower
                    value = self.password if not is_key else None
                    if value is None and not is_key:
                        value = self._saved_password()
                    if value is None:
                        before_prompt = time.monotonic()
                        value = self.prompt_secret('SSH key passphrase: ' if is_key else 'SSH password: ')
                        deadline += time.monotonic()-before_prompt
                    if '\n' in value or '\r' in value:
                        raise AuthenticationError('Passwords cannot contain newlines.')
                    if not is_key:
                        self.password = value
                    os.write(fd, (value+'\n').encode())
                    sent = True
            raise RuntimeError('SSH connection timed out.')
        finally:
            if not reaped:
                try:
                    os.kill(pid, signal.SIGTERM)
                    os.waitpid(pid, 0)
                except ProcessLookupError:
                    pass
            os.close(fd)

    def test_connection(self):
        try:
            self.connect_once()
            result = subprocess.run(self.command()+['python3 -'], input="print('HD2FX_SSH_OK')\n", text=True, capture_output=True, timeout=15)
            if result.returncode or result.stdout.strip() != 'HD2FX_SSH_OK':
                raise RuntimeError('SSH connected, but the guest Python check failed.')
        finally:
            subprocess.run(self.base()+['-O', 'exit', self.settings['host']], capture_output=True, timeout=10)
