#!/usr/bin/env python3
"""Copy exact audited Core sources; never imports/runs production entrypoints."""
from pathlib import Path
import hashlib
import json
import shutil
import sys

app = Path(__file__).resolve().parents[1]
root = app / 'CoreSnapshot/native-app-core-snapshot'
destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
for name in ('bridge.py', 'core_adapter.py'):
    target = destination / 'bridge' / name
    target.parent.mkdir(exist_ok=True)
    shutil.copyfile(app / 'bridge' / name, target)
names = ('launcher_version', 'dependencies', 'dependency_discovery', 'runtime_paths', 'fx_versions', 'fx_updates', 'update_checker')
manifest = {}
for relative in ['VERSION'] + ['launcher-20261026/' + name + '.py' for name in names]:
    source = root / relative
    target = destination / 'core' / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    manifest[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
(destination / 'core-source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
