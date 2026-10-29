"""Read-only update preflight. No installer, migration, backup or rollback writes.

These checks cannot authorize installation: trusted release/baseline and a tested
transaction worker are still absent. Unknown ownership always blocks replacement.
"""
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import unicodedata

INSTALL_ENABLED = False
PROTECTED_NAMES = frozenset(('settings.json','network-profile.json','known_hosts',
    '.git','.ssh','backups','reports','diagnostics','network-snapshots','history.jsonl',
    'presets','custom-presets','user-presets','fx.app','fex','proton','steam','gvproxy-eim'))


def inventory(root, settings_file, home=None):
    """Return storage locations, not their contents; never read the Keychain."""
    home = Path(home) if home is not None else Path.home()
    root,settings = Path(root),Path(settings_file)
    return {
        'settings_ssh_language_appearance':settings,
        'network_settings':settings.with_name('network-profile.json'),
        'network_snapshots':settings.parent/'network-snapshots',
        'diagnostics':home/'Library/Application Support/Helldivers2FXLauncher/Diagnostics',
        'profile_and_guest_backups':root/'launcher-20261026/backups',
        'environment_reports':root/'launcher-20261026/reports',
        'fx_preferences':home/'Library/Preferences/es.fxgam.steamac.plist',
        'external_proxy_preferences':home/'Library/Preferences/com.follow.clash.plist',
        'ssh_known_hosts':home/'.ssh/known_hosts',
        'keychain_service':'org.hd2fx.launcher.ssh-password.v1',
    }


def safe_relative(value):
    if not isinstance(value,str) or not value or '\\' in value or '\x00' in value:return False
    path = PurePosixPath(value)
    return (not path.is_absolute() and str(path)==value and
            all(part not in ('','.', '..') and ':' not in part and
                not any(unicodedata.category(c).startswith('C') for c in part)
                for part in value.split('/')))


def protected(value):
    if not safe_relative(value):return True
    parts = [part.casefold() for part in value.split('/')]
    return any(part in PROTECTED_NAMES or part.endswith(('.app','.keychain','.keychain-db'))
               or part.startswith(('proton-','fex-','id_rsa','id_ed25519')) for part in parts)


def managed_files(root):
    """The local reviewed draft is only a candidate list, never trusted hashes."""
    data = json.loads((Path(root)/'docs/update-managed-files.draft.json').read_text(encoding='utf-8'))
    files = data.get('files')
    if not isinstance(files,list) or len(files)!=len(set(files)) or any(protected(p) for p in files):
        raise ValueError('Invalid managed-file draft')
    return frozenset(files)


def fingerprint(path):
    """Detect concurrent file changes; do not follow symlinks or copy secret data."""
    path = Path(path)
    fd = os.open(path,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0))
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):raise ValueError('Not a regular file')
        digest = hashlib.sha256()
        while True:
            data = os.read(fd,65536)
            if not data:break
            digest.update(data)
        after = os.fstat(fd)
        if (before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns,before.st_ctime_ns)!=(
                after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns,after.st_ctime_ns):
            raise ValueError('File changed during inspection')
        return {'sha256':digest.hexdigest(),'mode':stat.S_IMODE(after.st_mode),'size':after.st_size}
    finally:os.close(fd)


def preflight(root, candidates, baseline=None):
    """Report conflicts only; no caller-supplied hashes can unlock installation."""
    root = Path(root).resolve();allowed = managed_files(root);conflicts = []
    seen = set()
    for value in candidates:
        if protected(value) or value not in allowed:
            conflicts.append((value,'protected_or_unmanaged'));continue
        alias = unicodedata.normalize('NFC',value).casefold()
        if alias in seen:
            conflicts.append((value,'duplicate_path'));continue
        seen.add(alias)
        path = root/value
        if any(parent.is_symlink() for parent in [path,*path.parents] if parent!=root and root in parent.parents):
            conflicts.append((value,'symlink'));continue
        expected = (baseline or {}).get(value)
        if not isinstance(expected,str) or not re.fullmatch('[a-f0-9]{64}',expected):
            conflicts.append((value,'unknown_ownership'));continue
        try:current = fingerprint(path)
        except (OSError,ValueError):
            conflicts.append((value,'missing_or_unreadable'));continue
        if current['sha256']!=expected:conflicts.append((value,'local_modification'))
    return {'install_allowed':False,'reason':'installer_unavailable','conflicts':conflicts}


def merge_defaults(existing, defaults):
    """Pure schema helper for future explicit migrations; never saves settings.

Unknown fields and existing values are retained. A type mismatch is a conflict,
not permission to reset user data. Callers must separately validate a new schema.
"""
    if not isinstance(existing,dict) or not isinstance(defaults,dict):
        raise ValueError('Expected settings objects')
    result = deepcopy(existing)
    for key,value in defaults.items():
        if key not in result:result[key] = deepcopy(value)
        elif isinstance(value,dict):
            if not isinstance(result[key],dict):raise ValueError('Configuration field type conflict')
            result[key] = merge_defaults(result[key],value)
    return result
