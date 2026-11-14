#!/usr/bin/env python3
"""Capture a clearly labelled DEBUG fixture window, never a real deployment result.

Creates and ad-hoc signs a temporary app copy with isolated preferences and the
updater disabled. No FX, SSH, guest, launch, or application-data action is run.
"""
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path, help='Built DEBUG .app')
parser.add_argument('output', type=Path, help='New PNG destination')
parser.add_argument('--scenario', required=True, choices=['completion', 'launch'])
parser.add_argument('--language', required=True, choices=['zh-CN', 'en'])
parser.add_argument('--appearance', required=True, choices=['dark', 'light'])
parser.add_argument('--width', type=int, default=1280)
parser.add_argument('--height', type=int, default=900)
args = parser.parse_args()
app = args.app.resolve()
output = args.output.resolve()
if not app.is_dir() or app.suffix != '.app':
    raise SystemExit('Expected a built DEBUG .app')
if output.exists() or output.suffix.lower() != '.png':
    raise SystemExit('Output must be a new .png file')
if args.width < 850 or args.height < 560:
    raise SystemExit('Requested size is below the app minimum')
output.parent.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix='hd2-ui-fixture-') as tmp:
    directory = Path(tmp)
    isolated = directory / 'FixturePreview.app'
    shutil.copytree(app, isolated, symlinks=True)
    plist = isolated / 'Contents' / 'Info.plist'
    info = plistlib.loads(plist.read_bytes())
    if info.get('CFBundleIdentifier') != 'com.lsjop.helldivers2fx.native.phase1':
        raise SystemExit('Unexpected source bundle identifier')
    executable_name = info.get('CFBundleExecutable', '')
    if not executable_name or '/' in executable_name:
        raise SystemExit('Unexpected executable name')
    executable = isolated / 'Contents' / 'MacOS' / executable_name
    binary = executable.read_bytes()
    # Xcode's Debug executable may be a stub that loads its sibling debug
    # dylib; Release bundles do not have this split fixture implementation.
    debug_name = executable_name + '.debug.dylib'
    debug_library = executable.parent / debug_name
    if debug_name.encode() in binary and debug_library.is_file():
        binary += debug_library.read_bytes()
    markers = (b'UI PREVIEW REFUSED', b'--preview-capture-request', b'--artwork-fixture-preview')
    if not all(marker in binary for marker in markers):
        raise SystemExit('This executable lacks the DEBUG fixture host; refusing to launch it')
    info['CFBundleIdentifier'] = 'com.lsjop.helldivers2fx.native.ui-review.' + uuid.uuid4().hex
    info['HD2UpdateServiceEnabled'] = 'NO'
    plist.write_bytes(plistlib.dumps(info))
    subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(isolated)], check=True, stdout=subprocess.DEVNULL)
    request = directory / 'capture-request.txt'
    apple_language = 'zh-Hans' if args.language == 'zh-CN' else 'en'
    launch_args = ['--artwork-fixture-preview', args.scenario,
                   '--preview-language', args.language, '--preview-appearance', args.appearance,
                   '--preview-capture-request', str(request), '--preview-width', str(args.width),
                   '--preview-height', str(args.height), '-AppleLanguages', '(' + apple_language + ')',
                   '-ApplePersistenceIgnoreState', 'YES', '-NSQuitAlwaysKeepsWindows', 'NO']
    subprocess.run(['/usr/bin/open', '-n', str(isolated), '--args', *launch_args], check=True)
    deadline = time.monotonic() + 35
    while not request.exists() and time.monotonic() < deadline:
        time.sleep(.1)
    if not request.exists():
        raise SystemExit('No fixture window appeared. Verify the app was built with DEBUG; no screenshot claimed.')
    window = request.read_text().strip()
    if not window.isdigit() or int(window) <= 0:
        raise SystemExit('Invalid window identifier')
    try:
        subprocess.run(['/usr/sbin/screencapture', '-x', '-o', '-l', window, str(output)], check=True, timeout=10)
    finally:
        Path(str(request) + '.ack').write_text('done')
    if not output.exists() or output.stat().st_size == 0:
        raise SystemExit('Capture failed')
    print(json.dumps({'type': 'DEBUG UI PREVIEW — SYNTHETIC DATA, NOT REAL', 'scenario': args.scenario,
                      'language': args.language, 'appearance': args.appearance, 'requested_size': [args.width, args.height],
                      'path': str(output), 'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}, ensure_ascii=False))
