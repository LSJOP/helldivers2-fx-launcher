#!/usr/bin/env python3
"""Capture only real App windows. Never render mock UI or modify captured pixels."""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import re
import subprocess
import time

parser=argparse.ArgumentParser()
parser.add_argument('bundle',type=Path);parser.add_argument('output',type=Path)
parser.add_argument('--language',required=True,choices=['zh-CN','en'])
parser.add_argument('--bootstrap-chinese',action='store_true',help='Use only with an isolated capture-copy bundle identifier')
args=parser.parse_args();bundle=args.bundle.resolve();output=args.output.resolve()
info=plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
if args.bootstrap_chinese and not info.get('CFBundleIdentifier','').startswith('com.lsjop.helldivers2fx.native.readme.'):
    raise SystemExit('Language bootstrap requires a separate capture bundle identifier')
initial='zh-CN' if args.bootstrap_chinese else args.language
output.mkdir(parents=True,exist_ok=True)
result_file=output/'readme-capture.json';request_file=output/'capture-request.json'
if result_file.exists() or request_file.exists():raise SystemExit('Use a fresh capture directory')
launch_args=['--readme-screenshots',str(output),args.language,
             '-NativeLanguage',initial,'-AppleLanguages','(zh-Hans)' if initial=='zh-CN' else '(en)',
             '-NativeRememberedRuntimeRoot','',
             '-NativeCredentialAutoLoadDisabled','YES','-ApplePersistenceIgnoreState','YES','-NSQuitAlwaysKeepsWindows','NO']
subprocess.run(['/usr/bin/open','-n',str(bundle),'--args',*launch_args],check=True)
seen=set();started=time.monotonic();deadline=started+90;reopened=False
while time.monotonic()<deadline:
    if not reopened and time.monotonic()-started>3 and not request_file.exists():
        subprocess.run(['/usr/bin/open',str(bundle)],check=True) # Native reopen event if launch restored no window.
        reopened=True
    if result_file.exists():
        result=json.loads(result_file.read_text())
        if result.get('result')!='PASS':raise SystemExit(json.dumps(result))
        result['sha256']={name:hashlib.sha256((output/name).read_bytes()).hexdigest() for name in result['files']}
        result_file.write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result,indent=2));raise SystemExit(0)
    try:
        request=json.loads(request_file.read_text());token,name,window=request['token'],request['file'],request['window']
        if token not in seen:
            if not re.fullmatch(r'[A-Fa-f0-9-]{36}',token) or not re.fullmatch(r'[a-z-]+\.png',name) or type(window)is not int or window<=0:raise ValueError('Invalid capture request')
            seen.add(token)
            shot=subprocess.run(['/usr/sbin/screencapture','-x','-o','-l',str(window),str(output/name)],capture_output=True,timeout=5)
            (output/(token+'.ack')).write_text('OK' if shot.returncode==0 else 'FAIL')
    except FileNotFoundError:pass
    time.sleep(.05)
raise SystemExit('Real-window capture timed out; no screenshot acceptance claimed')
