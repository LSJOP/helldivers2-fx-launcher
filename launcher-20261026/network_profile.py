"""Opt-in, reversible macOS wired profile. Does not configure FX or FlClash."""
import copy
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile

DEFAULTS = {'version': 1, 'check_before_launch': False, 'restore_wifi': [], 'phase': None}


class ProfileError(RuntimeError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def settings_path(launcher_settings):
    return Path(launcher_settings).with_name('network-profile.json')


def load(path):
    if not Path(path).exists():
        return copy.deepcopy(DEFAULTS)
    try:
        data = json.loads(Path(path).read_text(encoding='utf-8'))
        assert data['version'] == 1 and type(data['check_before_launch']) is bool
        devices = data['restore_wifi']
        assert isinstance(devices, list) and len(set(devices)) == len(devices)
        assert all(isinstance(v, str) and re.fullmatch(r'en[0-9]+', v) for v in devices)
        assert data.get('phase') in [None, 'applying', 'applied', 'restoring', 'restored', 'rollback_failed']
        return {'version': 1, 'check_before_launch': data['check_before_launch'],
                'restore_wifi': devices, 'phase': data.get('phase')}
    except (OSError, ValueError, KeyError, TypeError, AssertionError):
        raise ProfileError('settings_invalid') from None


def save(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.network-profile-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(data, stream, indent=2)
            stream.write('\n')
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _command(args, required=True):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=4,
                                env=dict(os.environ, LC_ALL='C', LANG='C'))
    except (OSError, subprocess.TimeoutExpired):
        raise ProfileError('check_failed') from None
    if result.returncode:
        if required:
            raise ProfileError('check_failed')
        return ''
    return result.stdout


def hardware_ports():
    if sys.platform != 'darwin':
        raise ProfileError('mac_only')
    raw = _command(['/usr/sbin/networksetup', '-listallhardwareports'])
    ports = re.findall(r'^Hardware Port:\s*(.*?)\r?\nDevice:\s*(\w+)', raw, re.M)
    if not ports:
        raise ProfileError('check_failed')
    return {device: name for name, device in ports}


def wifi_power(device):
    raw = _command(['/usr/sbin/networksetup', '-getairportpower', device])
    match = re.search(r':\s*(On|Off)\s*$', raw, re.I)
    return match[1].lower() == 'on' if match else None


def inspect():
    ports = hardware_ports()
    wireless = [device for device, name in ports.items() if name.lower() in ['wi-fi', 'wifi', 'airport']]
    route = _command(['/sbin/route', '-n', 'get', '-inet', 'default'], required=False)
    match = re.search(r'^\s*interface:\s*(\w+)\s*$', route, re.M)
    interface = match[1] if match else None
    name = ports.get(interface, '')
    wired = bool(interface and interface not in wireless and
                 re.search(r'ethernet|\blan\b|以太网', name, re.I))
    if wired:
        wired = bool(_command(['/usr/sbin/ipconfig', 'getifaddr', interface], required=False).strip())
    wifi = [{'device': device, 'on': wifi_power(device)} for device in wireless]
    try:
        with socket.create_connection(('127.0.0.1', 7890), timeout=.5):
            proxy = True
    except OSError:
        proxy = False
    return {'default_interface': interface, 'wired_default': wired, 'wifi': wifi,
            'proxy_available': proxy, 'ready': wired and all(row['on'] is False for row in wifi)}


def _set_wifi(device, on):
    try:
        _command(['/usr/sbin/networksetup', '-setairportpower', device, 'on' if on else 'off'])
        if wifi_power(device) is not on:
            raise ProfileError('wifi_change_failed')
    except ProfileError:
        raise ProfileError('wifi_change_failed') from None


def success_conditions():
    """Read local conditions without changing FlClash or assuming its live node."""
    route = _command(['/sbin/route', '-n', 'get', '-inet', '1.1.1.1'], required=False)
    match = re.search(r'^\s*interface:\s*(\w+)', route, re.M)
    device = match[1] if match else None
    proxy = _command(['/usr/sbin/scutil', '--proxy'], required=False)
    result = {'tun_route':device.startswith('utun') if device else None,
              'system_proxy':bool(re.search(r'\b(?:HTTP|HTTPS|SOCKS)Enable\s*:\s*1\b',proxy)) if proxy else None,
              'flclash_mode':None, 'allow_lan':None}
    path = Path.home()/'Library/Application Support/com.follow.clash/config.yaml'
    try:
        text = path.read_text()
    except OSError:
        return result
    # Only top-level scalar keys; never deserialize node passwords/subscriptions.
    mode = re.search(r'''^mode:\s*["']?(global|rule|direct)["']?\s*$''', text, re.M)
    lan = re.search(r'^allow-lan:\s*(true|false)\s*$', text, re.M)
    result['flclash_mode'] = mode[1] if mode else None
    result['allow_lan'] = lan[1]=='true' if lan else None
    return result


def apply(path):
    before = inspect()
    # Never disconnect the only active/default network, or change service order.
    if not before['wired_default']:
        raise ProfileError('need_wired')
    if not before['proxy_available']:
        raise ProfileError('need_proxy')
    if any(row['on'] is None for row in before['wifi']):
        raise ProfileError('wifi_unknown')
    original = load(path)
    data = copy.deepcopy(original)
    targets = [row['device'] for row in before['wifi'] if row['on']]
    data['restore_wifi'] = sorted(set(data['restore_wifi'] + targets))
    data['phase'] = 'applying'
    save(path, data)  # Recovery information must reach disk before any change.
    changed = []
    try:
        for device in targets:
            changed.append(device)  # Include a change whose verification may fail.
            _set_wifi(device, False)
        after = inspect()
        if not after['ready'] or after['default_interface'] != before['default_interface']:
            raise ProfileError('need_wired')
        data.update(check_before_launch=True, phase='applied')
        save(path, data)
        return after
    except (Exception, KeyboardInterrupt) as error:
        failed = []
        for device in changed:
            try:
                _set_wifi(device, True)
            except Exception:
                failed.append(device)
        recovery = copy.deepcopy(original)
        recovery['restore_wifi'] = sorted(set(recovery['restore_wifi'] + failed))
        if failed:
            recovery['phase'] = 'rollback_failed'
        save(path, recovery)
        if isinstance(error, KeyboardInterrupt):
            raise
        raise ProfileError('rollback_failed' if failed else 'apply_failed_restored') from None


def restore(path):
    data = load(path)
    ports = hardware_ports() if data['restore_wifi'] else {}
    for device in data['restore_wifi']:
        if ports.get(device, '').lower() not in ['wi-fi', 'wifi', 'airport']:
            raise ProfileError('wifi_changed')
    data.update(check_before_launch=False, phase='restoring')
    save(path, data)
    changed = False
    for device in list(data['restore_wifi']):
        _set_wifi(device, True)
        changed = True
        data['restore_wifi'].remove(device)
        save(path, data)
    data['phase'] = 'restored'
    save(path, data)
    return changed


def toggle_check(path):
    data = load(path)
    data['check_before_launch'] = not data['check_before_launch']
    save(path, data)
    return data['check_before_launch']
