#!/usr/bin/env python3
"""Coordinates DEBUG UI capture, scoped to window IDs emitted by the app itself."""
import json
from pathlib import Path
import re
import subprocess
import sys
import time

bundle, directory = (Path(value).resolve() for value in sys.argv[1:3])
directory.mkdir(parents=True, exist_ok=True)
takeover = '--takeover' in sys.argv[3:]
queue = '--task-queue' in sys.argv[3:]
ux = '--ux-refinement' in sys.argv[3:]
refinement = '--ui-refinement' in sys.argv[3:]
focused = '--menu-review-only' in sys.argv[3:]
result_file = directory / ('takeover-review.json' if takeover else 'ux-review.json' if ux else 'queue-review.json' if queue else 'refinement-review.json' if refinement else 'menu-review.json' if focused else 'gui-smoke.json')
request_file = directory / 'capture-request.json'
for path in (result_file, request_file):
    if path.exists(): path.unlink()
subprocess.run(['/usr/bin/open', '-n', str(bundle), '--args', '--takeover-smoke' if takeover else '--ux-refinement-smoke' if ux else '--task-queue-smoke' if queue else '--ui-refinement-smoke' if refinement else '--ui-v2-menu-review' if focused else '--phase1-smoke', str(directory), '--external-capture'] + ([flag for flag in ('--hero-only', '--page-polish') if flag in sys.argv[3:]]), check=True)
seen = set()
deadline = time.monotonic() + 240
while time.monotonic() < deadline:
    if result_file.exists():
        result = json.loads(result_file.read_text())
        if takeover or focused or refinement or queue or ux:
            print(json.dumps(result, ensure_ascii=False, indent=2))
            raise SystemExit(0 if result.get('result') == 'PASS' else 1)
        print(json.dumps({key: result.get(key) for key in ('programmatic_result', 'native_menu_actions', 'visual_capture', 'bridge_loaded', 'error_propagation', 'error_recovery', 'error')}, indent=2))
        raise SystemExit(0 if result.get('programmatic_result') == 'PASS' and result.get('visual_capture') == 'PASS' else 1)
    try:
        request = json.loads(request_file.read_text())
        token, name, window = request['token'], request['file'], request['window']
        if token not in seen:
            if not re.fullmatch(r'[A-Fa-f0-9-]{36}', token) or not re.fullmatch(r'[a-z-]+\.png', name) or type(window) is not int or window <= 0:
                raise ValueError('Invalid capture request')
            seen.add(token)
            result = subprocess.run(['/usr/sbin/screencapture', '-x', '-o', '-l', str(window), str(directory / name)], capture_output=True, timeout=5)
            (directory / (token + '.ack')).write_text('OK' if result.returncode == 0 else 'FAIL')
    except FileNotFoundError:
        pass
    time.sleep(0.05)
raise SystemExit('GUI capture timed out')
