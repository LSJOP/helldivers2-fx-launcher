"""Shared, bounded launch-resource validation. No target code is imported or run."""
import hashlib
import os
from pathlib import Path
import stat
import subprocess

REQUIRED = ('launcher-20261026/steam-cdp.mjs', 'tools/check_node.cjs',
            'goal-fx-multiplayer-20261026/gvproxy-eim-wrapper')
FX_REQUIREMENT = ('anchor apple generic and identifier "es.fxgam.steamac" and '
                  'certificate leaf[subject.OU] = "V25VKGTW55"')


def digest_file(base, relative, limit=2 * 1024 * 1024):
    path = Path(base)
    for part in Path(relative).parts:
        path = path / part
        if path.is_symlink():
            return None, 'unsafe_path'
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
        with os.fdopen(fd, 'rb') as stream:
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode) or before.st_size > limit:
                return None, 'invalid_file'
            payload = stream.read(limit + 1)
            after = os.fstat(stream.fileno())
            if len(payload) > limit or (before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                return None, 'file_changed'
            return hashlib.sha256(payload).hexdigest(), 'present'
    except FileNotFoundError:
        return None, 'missing'
    except IsADirectoryError:
        return None, 'invalid_file'
    except OSError:
        return None, 'unreadable'


def inspect_resources(root, archive):
    root, archive = Path(root), Path(archive)
    files = []
    for relative in REQUIRED:
        actual, state = digest_file(root, relative)
        expected, expected_state = digest_file(archive, relative)
        files.append({'file': relative, 'actual_path': str(root / relative),
                      'expected_path': str(archive / relative), 'actual_sha256': actual,
                      'expected_sha256': expected,
                      'state': 'archive_missing' if expected_state != 'present' else
                               'match' if actual and actual == expected else
                               'hash_mismatch' if actual else state})
    return {'runtime_root': str(root), 'archive_root': str(archive),
            'archive_files_match': all(row['state'] == 'match' for row in files),
            'resource_files': files}


def fx_integrity(app, historical_hash):
    """Accept pinned history OR a sealed bundle signed by the verified FX publisher.

    The observed hash is never its own trust anchor. A publisher requirement must
    pass before binding that hash to all original profile/process/Guest guards.
    No version-number allowlist and no unsigned/ad-hoc fallback.
    """
    app = Path(app)
    relative = 'Contents/MacOS/steamac-vm'
    actual, state = digest_file(app, relative, 512 * 1024 * 1024)
    evidence = {'fx_path': str(app), 'actual_path': str(app / relative),
                'actual_sha256': actual, 'historical_sha256': historical_hash,
                'state': state, 'trust': 'unverified'}
    if not actual:
        return evidence
    if actual == historical_hash:
        evidence.update(state='verified', trust='pinned_archive')
        return evidence
    try:
        result = subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict',
                                 '-R=' + FX_REQUIREMENT, str(app)],
                                capture_output=True, timeout=15)
        fresh, _ = digest_file(app, relative, 512 * 1024 * 1024)
        if result.returncode == 0 and fresh == actual:
            evidence.update(state='verified', trust='fx_publisher_signature')
        else:
            evidence['state'] = 'signature_invalid'
    except (OSError, subprocess.TimeoutExpired):
        evidence['state'] = 'signature_unavailable'
    return evidence
