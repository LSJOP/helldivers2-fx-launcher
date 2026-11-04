#!/usr/bin/env python3
"""Record an independent development bundle without touching Latest or user state."""
import hashlib
import json
import os
import re
from pathlib import Path
import stat
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
root = Path(__file__).resolve().parents[2]
metadata = json.loads((app / 'Contents/Resources/BuildMetadata.json').read_text())
entries = []
for directory, folders, files in os.walk(app, followlinks=False):
    for name in sorted(folders + files):
        p = Path(directory) / name
        st = p.lstat()
        relative = str(p.relative_to(app))
        if p.is_symlink():
            entries.append([relative, 'link', os.readlink(p)])
        elif p.is_file():
            entries.append([relative, oct(stat.S_IMODE(st.st_mode)), hashlib.sha256(p.read_bytes()).hexdigest()])
tracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z', 'native-app'], text=True).split('\0')
sources = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in tracked if p and (root / p).is_file() and not (root / p).is_symlink()}
evidence = root / 'native-app/evidence'
swift_cases = {}
for name in ['ssh','native-core','native-integration','fx-identity','launch','credential-swift','performance','fx-selection','deployment']:
    text = (evidence / (name + '-checks.txt')).read_text()
    patterns = [r'PASS: (\d+) FX selection checks', r'TOTAL (\d+) passed, 0 failed', r'SSH checks: (\d+) passed, 0 failed', r'(\d+) (?:launch and GUI state|credential|performance inference and editor state|FX selection|deployment) checks (?:PASS|passed)']
    match = next((m for p in patterns if (m := re.search(p, text))), None)
    if not match: raise SystemExit('Missing passing test result: ' + name)
    swift_cases[name] = int(match.group(1))
python_cases = {}
for name in ['localization-negative','readme-screenshot','release-history','update-resources']:
    text = (evidence / (name + '-checks.txt')).read_text()
    match = re.search(r'Ran (\d+) tests', text)
    if not match or not text.rstrip().endswith('OK'): raise SystemExit('Missing passing Python result: ' + name)
    python_cases[name] = int(match.group(1))
if '15/15 documentation checks PASS' not in (evidence / 'docs-checks.txt').read_text(): raise SystemExit('Documentation gate missing')
record = {
    'app': str(app), 'metadata': metadata,
    'git_head': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
    'executable_sha256': hashlib.sha256((app / 'Contents/MacOS/HD2FXNative').read_bytes()).hexdigest(),
    'bundle_manifest_sha256': hashlib.sha256(json.dumps(sorted(entries), separators=(',', ':')).encode()).hexdigest(),
    'source_manifest_sha256': hashlib.sha256(json.dumps(sources, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
    'bundle_files': len(entries), 'source_files': len(sources),
    'tests': {'swift_checks': sum(swift_cases.values()), 'python_checks': sum(python_cases.values()), 'swift_cases': swift_cases, 'python_cases': python_cases, 'documentation_checks': 15, 'fresh_vm_game_eac_multiplayer': 'NOT_TESTED'},
    'source_files_sha256': sources,
}
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({k: v for k, v in record.items() if k != 'source_files_sha256'}, indent=2))
