"""Read-only plans and narrowly scoped Guest transactions. No import-time IO.

Sent over the existing SSH transport; never installed in the Guest. IO is injected
so the same transaction code can be tested without SSH, sudo, systemd or /proc.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

PROXY_TEXT = '# HD2 helper: runtime only\n[Service]\nEnvironment="https_proxy=http://192.168.127.254:7890" "http_proxy=http://192.168.127.254:7890"\n'
LEGACY_PROXY_TEXT = PROXY_TEXT.replace('192.168.127.254:7890', '127.0.0.1:17890')
IPV6_KEYS = ('all', 'default', 'eth0', 'lo')


class NativeGuest:
    def boot(self):
        return Path('/proc/sys/kernel/random/boot_id').read_text().strip()

    def marker(self):
        return 'steamac.gfx=vulkan' in Path('/proc/cmdline').read_text().split()

    def ipv6(self):
        base = Path('/proc/sys/net/ipv6/conf')
        return {p.parent.name: p.read_text().strip() for p in base.glob('*/disable_ipv6')}

    def set_ipv6(self, key, value):
        if not re.fullmatch(r'[A-Za-z0-9_.:-]+', key):
            raise RuntimeError('Invalid interface name')
        (Path('/proc/sys/net/ipv6/conf')/key/'disable_ipv6').write_text(value)

    def proxy_path(self):
        return Path('/run/user')/str(os.getuid())/'systemd/user/steam.service.d/90-hd2-proxy.conf'

    def proxy(self):
        p = self.proxy_path()
        if p.is_symlink() or p.parent.is_symlink():
            raise RuntimeError('Proxy path is a symlink; left unchanged')
        return p.read_text() if p.exists() else None

    def set_proxy(self, value):
        p = self.proxy_path()
        self.proxy()  # Repeat symlink check immediately before writing.
        if value is None:
            if p.exists(): p.unlink()
        else:
            p.parent.mkdir(parents=True, exist_ok=True)
            temporary = p.with_name('.hd2-proxy-'+str(os.getpid()))
            fd = os.open(temporary, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
            try:
                with os.fdopen(fd, 'w') as stream: stream.write(value)
                temporary.replace(p)
            finally:
                if temporary.exists(): temporary.unlink()

    def service(self):
        r = subprocess.run(['systemctl','--user','show','steam.service',
                            '--property=LoadState,ActiveState,SubState,ControlGroup'],
                           capture_output=True, text=True, check=True, timeout=10)
        values = dict(row.split('=', 1) for row in r.stdout.splitlines() if '=' in row)
        if values.get('LoadState') != 'loaded':
            raise RuntimeError('Steam service is not loaded')
        state = values.get('ActiveState')
        if state == 'active' and values.get('SubState') == 'running': return 'running'
        if state in ('inactive','failed'): return 'stopped'
        raise RuntimeError('Steam service is transitioning or unknown')

    def idle(self):
        # Do not stop Steam if any reaper/game is present. No global kill commands.
        for name in ('reaper', 'helldivers2.exe'):
            r = subprocess.run(['pgrep','-x',name], capture_output=True, timeout=5)
            if r.returncode == 0: raise RuntimeError('A game or Steam launch is active')
            if r.returncode != 1: raise RuntimeError('Cannot verify active games')

    def managed_steam(self):
        r = subprocess.run(['pgrep','-x','steam'], capture_output=True, text=True, timeout=5)
        if r.returncode not in (0,1): raise RuntimeError('Cannot inspect Steam processes')
        group = subprocess.run(['systemctl','--user','show','steam.service','--value','--property=ControlGroup'],
                               capture_output=True, text=True, check=True, timeout=10).stdout.strip()
        for pid in r.stdout.split():
            groups = [line.split(':',2)[-1] for line in (Path('/proc')/pid/'cgroup').read_text().splitlines()]
            if not group or not any(g == group or g.startswith(group+'/') for g in groups):
                raise RuntimeError('Independent Steam instance; leave it running and exit it normally')

    def service_action(self, action):
        args = ['systemctl','--user',action]
        if action != 'daemon-reload': args.append('steam.service')
        result = subprocess.run(args, capture_output=True, text=True, timeout=20)
        if result.returncode:
            raise RuntimeError('Steam service '+action+' failed: '+(result.stderr.strip()[-600:] or 'exit '+str(result.returncode)))


def guard(io, boot):
    if not boot or io.boot() != boot or not io.marker():
        raise RuntimeError('Guest identity changed or is unverified; no Guest writes allowed')


def inspect(io):
    ipv6 = io.ipv6()
    if any(ipv6.get(k) not in ('0','1') for k in IPV6_KEYS) or any(v not in ('0','1') for v in ipv6.values()):
        raise RuntimeError('Cannot read required Guest IPv6 switches')
    return {'boot': io.boot(), 'marker': io.marker(), 'ipv6': ipv6,
            'proxy': io.proxy(), 'service': io.service()}


def ipv6_expected(before):
    result = dict(before)
    if before['all'] != '1':
        # Linux conf/all can affect every interface, including non-target ones.
        result.update({k: '1' for k in result})
    result.update({k:'1' for k in IPV6_KEYS})
    return result


def restore_ipv6(io, boot, before, expected):
    guard(io, boot)
    now = io.ipv6()
    if set(now) != set(before): raise RuntimeError('Guest interfaces changed; manual IPv6 recovery required')
    changed = [k for k in before if before[k] != expected[k]]
    if any(now[k] not in (before[k], expected[k]) for k in changed):
        raise RuntimeError('IPv6 changed externally; manual recovery required')
    # Restoring all first can cascade; restore the interface snapshot afterwards.
    if 'all' in changed and now['all'] != before['all']:
        io.set_ipv6('all', before['all'])
    for key in before:
        if key == 'all': continue
        current = io.ipv6()[key]
        if current != before[key]:
            # all's cascade is included in the approved/recorded transaction.
            if key not in changed and now[key] != before[key]:
                raise RuntimeError('Unrelated interface changed; manual recovery required')
            io.set_ipv6(key, before[key])
    if io.ipv6() != before: raise RuntimeError('IPv6 restoration could not be verified')


def apply_ipv6(io, plan):
    before, boot = plan['ipv6'], plan['boot']
    guard(io, boot)
    io.idle()
    if io.ipv6() != before: raise RuntimeError('IPv6 plan changed; obtain new consent')
    expected = ipv6_expected(before)
    attempted = False
    try:
        for key in IPV6_KEYS:
            if io.ipv6()[key] != '1':
                attempted = True
                io.set_ipv6(key, '1')
        after = io.ipv6()
        if after != expected: raise RuntimeError('IPv6 write verification failed')
        return {'ok':True, 'changed':attempted, 'before':before, 'after':after, 'recovery':'not needed'}
    except Exception as error:
        recovered = not attempted
        if attempted:
            try: restore_ipv6(io, boot, before, expected); recovered = True
            except Exception: recovered = False
        return {'ok':False, 'changed':attempted, 'reason':str(error),
                'recovery':'restored' if recovered else 'manual IPv6 recovery required'}


def restore_proxy(io, boot, before, target, original_service):
    guard(io, boot)
    io.idle()
    current = io.proxy()
    if current not in (before,target): raise RuntimeError('Proxy changed externally; manual recovery required')
    running = io.service() == 'running'
    # A successful restart may already be using the new environment. Restoring
    # the file alone does not restore that process environment.
    if running and current != before:
        io.managed_steam()
        io.service_action('stop')
        if io.service() != 'stopped': raise RuntimeError('Steam recovery stop failed')
    if io.proxy() != current:
        raise RuntimeError('Proxy changed during recovery; left unchanged')
    if current != before: io.set_proxy(before)
    io.service_action('daemon-reload')
    # Recovery never starts an originally stopped service or stops a running one.
    if original_service == 'running' and io.service() == 'stopped':
        io.managed_steam()
        io.service_action('start')
        if io.service() != 'running': raise RuntimeError('Steam recovery start failed')
    if io.proxy() != before: raise RuntimeError('Proxy recovery verification failed')


def apply_proxy(io, plan, enabled):
    boot, before, original = plan['boot'], plan['proxy'], plan['service']
    target = PROXY_TEXT if enabled else None
    guard(io, boot)
    if before not in (None, PROXY_TEXT, LEGACY_PROXY_TEXT):
        raise RuntimeError('Unknown proxy content; left unchanged')
    if io.proxy() != before or io.service() != original:
        raise RuntimeError('Proxy/service plan changed; obtain new consent')
    io.idle(); io.managed_steam()
    changed = False
    try:
        if original == 'running':
            changed = True  # Include stop failures which may have taken effect.
            io.service_action('stop')
            if io.service() != 'stopped': raise RuntimeError('Steam did not stop')
            io.managed_steam()  # No independently running Steam may remain.
        if io.proxy() != before:
            raise RuntimeError('Proxy changed during stop; left unchanged')
        if before != target:
            changed = True
            io.set_proxy(target)
        io.service_action('daemon-reload')
        if original == 'running':
            io.service_action('reset-failed'); io.service_action('start')
            if io.service() != 'running': raise RuntimeError('Steam restart failed')
        if io.proxy() != target: raise RuntimeError('Proxy write verification failed')
        return {'ok':True, 'changed':changed, 'before':before, 'after':target,
                'original_service':original, 'recovery':'not needed'}
    except Exception as error:
        try:
            restore_proxy(io,boot,before,target,original)
            recovery = 'restored'
        except Exception:
            recovery = 'manual proxy/Steam recovery required'
        return {'ok':False, 'changed':changed, 'reason':str(error), 'recovery':recovery}


def ensure_steam(io, boot):
    guard(io, boot)
    original = io.service()
    if original == 'running': return {'ok':True, 'started':False}
    io.idle(); io.managed_steam()
    io.service_action('reset-failed')
    io.service_action('start')  # Exactly one attempt, no retry loop.
    if io.service() != 'running': raise RuntimeError('Steam controlled start failed')
    return {'ok':True, 'started':True}


def log_cursor(path):
    # One open file descriptor binds identity and contents, avoiding rename races.
    with path.open('rb') as stream:
        stat = os.fstat(stream.fileno())
        size = stat.st_size
        prefix = stream.read(min(size, 256))
        stream.seek(max(0, size-256)); tail = stream.read(size-max(0,size-256))
    return {'dev':stat.st_dev, 'ino':stat.st_ino, 'offset':size,
            'prefix':hashlib.sha256(prefix).hexdigest(),
            'tail':hashlib.sha256(tail).hexdigest()}


def eac_baseline(base):
    files = {}
    for p in base.glob('*/AppData/Roaming/EasyAntiCheat/**/anticheatlauncher.log'):
        files[str(p)] = log_cursor(p)
    return {'files':files, 'valid':True}


def eac_poll(base, baseline):
    # Keep the launch baseline immutable. Re-read only its suffix so markers split
    # across polls can be combined without borrowing any pre-launch bytes.
    if not baseline or not baseline.get('valid'): return {'result':'unverified'}
    results = []; paths = list(base.glob('*/AppData/Roaming/EasyAntiCheat/**/anticheatlauncher.log'))
    for p in paths:
        old = baseline['files'].get(str(p))
        if old is None:
            # A new path could be a rotated old file. Establish a cursor and wait
            # for further writes rather than trusting all of its contents.
            baseline['files'][str(p)] = log_cursor(p)
            continue
        with p.open('rb') as stream:
            stat = os.fstat(stream.fileno())
            same = (stat.st_dev,stat.st_ino) == (old['dev'],old['ino']) and stat.st_size >= old['offset']
            if same:
                prefix = stream.read(min(old['offset'],256))
                stream.seek(max(0,old['offset']-256)); tail = stream.read(min(old['offset'],256))
                same = (hashlib.sha256(prefix).hexdigest() == old['prefix'] and
                        hashlib.sha256(tail).hexdigest() == old['tail'])
            if not same:
                baseline['files'][str(p)] = log_cursor(p)
                continue
            stream.seek(old['offset'])
            # Oversized suffix: cannot prove a complete launch sequence.
            if stat.st_size-old['offset'] > 1024*1024: continue
            text = stream.read(stat.st_size-old['offset']).decode('utf-8',errors='replace')
        exits = re.findall(r'Terminating with:\s*(\d+)',text)
        if exits and int(exits[-1]) != 0:
            results.append({'result':'failed','exit_code':int(exits[-1])})
        elif exits and int(exits[-1]) == 0 and 'Launcher finished with: 301' in text and 'Successfully initialized the Easy Anti-Cheat module' in text:
            results.append({'result':'passed'})
    failure = next((r for r in results if r['result']=='failed'),None)
    # Multiple logs producing success are ambiguous.
    result = failure or ({'result':'passed'} if len(results)==1 else {'result':'pending' if paths else 'unverified'})
    return dict(result, baseline=baseline)


def dispatch(request):
    io = NativeGuest()
    action = request['action']
    if action == 'inspect': return inspect(io)
    if action == 'idle':
        guard(io,request['boot']); io.idle(); return {'ok':True}
    if action == 'ipv6': return apply_ipv6(io, request['plan'])
    if action == 'restore_ipv6':
        io.idle()
        restore_ipv6(io,request['boot'],request['before'],request['after']); return {'ok':True}
    if action == 'proxy': return apply_proxy(io,request['plan'],request['enabled'])
    if action == 'restore_proxy':
        restore_proxy(io,request['boot'],request['before'],request['after'],request['original_service']); return {'ok':True}
    if action == 'steam':
        try: return ensure_steam(io,request['boot'])
        except Exception as error:
            return {'ok':False,'reason':str(error)}
    if action in ('eac_baseline','eac_poll'):
        base = Path.home()/'.local/share/Steam/steamapps/compatdata/553850/pfx/drive_c/users'
        return eac_baseline(base) if action == 'eac_baseline' else eac_poll(base,request['baseline'])
    raise RuntimeError('Unknown safety operation')
