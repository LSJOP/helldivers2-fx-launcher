#!/usr/bin/env python3
"""Lightweight local README image checks. Content language still needs visual review."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote,urlparse

ROOT=Path(__file__).resolve().parents[2]

def ui_fingerprint(root):
    files=sorted([*(root/'native-app/Views').rglob('*.swift'),*(root/'native-app/App').rglob('*.swift'),root/'native-app/Models/Navigation.swift',root/'native-app/bridge/native-locales.json'])
    return hashlib.sha256(''.join(str(p.relative_to(root))+':'+hashlib.sha256(p.read_bytes()).hexdigest()+'\n' for p in files if p.is_file()).encode()).hexdigest()

def check(root):
    errors=[];count=0
    manifest_path=root/'docs/images/manifest.json'
    try:manifest=json.loads(manifest_path.read_text())
    except (OSError,ValueError):return ['Missing or invalid screenshot provenance manifest'],0
    try:records={item['path']:item for item in manifest.get('screenshots',[])}
    except (KeyError,TypeError,AttributeError):return ['Invalid screenshot provenance records'],0
    reviewed=manifest.get('reviewed_ui_source_sha256',manifest.get('ui_source_sha256'))
    if reviewed and reviewed!=ui_fingerprint(root):errors.append('UI source changed since screenshot review; recapture visible changes or explicitly document/review unchanged UI')
    for name,language in [('README.md','en'),('README.zh-CN.md','zh-CN')]:
        path=root/name
        if not path.is_file():errors.append(name+': missing README');continue
        source=path.read_text()
        images=re.findall(r'!\[[^\]]*\]\(<?([^\s)>]+)>?(?:\s+"[^"]*")?\)',source)
        images+=re.findall(r'<img\b[^>]*\bsrc=[\"\']([^\"\']+)',source,re.I)
        for image in images:
            parsed=urlparse(image)
            if parsed.scheme or parsed.netloc:continue # Badges/external media are not content-language evidence.
            local=unquote(parsed.path)
            target=root/local
            if not target.resolve().is_relative_to(root.resolve()):errors.append(name+': image outside repository '+local);continue
            if not target.is_file():errors.append(name+': missing local image '+local);continue
            if local.startswith(('docs/images/','docs/screenshots/')):
                count+=1
                expected='docs/images/'+language+'/'
                if not local.startswith(expected):errors.append(name+': wrong screenshot language directory '+local)
                record=records.get(local)
                if not record:errors.append(name+': screenshot has no provenance '+local);continue
                if record.get('language')!=language or record.get('visual_review')!='PASS':errors.append(name+': language/visual review missing '+local)
                if record.get('sha256')!=hashlib.sha256(target.read_bytes()).hexdigest():errors.append(name+': screenshot bytes changed since review '+local)
        for other in ('README.md','README.zh-CN.md'):
            if ']('+other+')' not in source:errors.append(name+': relative language link missing '+other)
    if count==0:errors.append('No localized README screenshots referenced; document missing captures explicitly')
    return errors,count

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,default=ROOT);args=parser.parse_args()
    errors,count=check(args.root)
    if errors:
        for error in errors:print('FAIL '+error)
        return 1
    print('PASS '+str(count)+' localized README screenshot references: files, language directories, provenance and hashes')
    print('Path checks do not establish screenshot content language; recorded visual review is required.')
    return 0
if __name__=='__main__':sys.exit(main())
