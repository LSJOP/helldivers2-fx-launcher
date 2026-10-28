"""Local-only dependency inspection: no SSH, app launch, network or writes."""
import hashlib
import json
import platform
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    data = json.loads((ROOT/'runtime-requirements.json').read_text(encoding='utf-8'))
    missing = []
    print('Source package; game launch / fresh-machine compatibility: unverified')
    print('Host:', platform.system(), platform.machine())
    if platform.system() != 'Darwin' or platform.machine() not in ('arm64', 'aarch64'):
        missing.append('Apple Silicon macOS host (other hosts unverified)')
    if sys.version_info < (3, 9):
        missing.append('Python >= 3.9')
    for name in ('ssh', 'zsh', 'node'):
        print(name+':', 'available' if shutil.which(name) else 'missing')
        if not shutil.which(name):
            missing.append(name)
    print('Node global fetch / WebSocket: unverified (not executed)')
    for item in data['components']:
        if 'path' not in item:
            print(item['name']+': guest component unverified (no SSH performed)')
            continue
        path = ROOT/item['path']
        if not path.is_file():
            print(item['name']+': missing (intentionally excluded from source package)')
            missing.append(item['name'])
        elif hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            print(item['name']+': hash mismatch')
            missing.append(item['name']+' hash mismatch')
        else:
            print(item['name']+': expected local file hash matches; runtime unverified')
    print('Guest / Steam / game / EAC / multiplayer: unverified')
    return 2 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
