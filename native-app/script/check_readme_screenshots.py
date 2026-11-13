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
    files=sorted([*(root/'native-app/Views').rglob('*.swift'),*(root/'native-app/App').rglob('*.swift'),root/'native-app/Models/Navigation.swift',root/'native-app/Resources/native-locales.json'])
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
    primary=root/'README.md'
    if not primary.is_file():return errors+['README.md: missing README'],count
    readme=primary.read_text()
    zh_anchor='<a id="zh-cn"></a>'
    en_anchor='<a id="english"></a>'
    if zh_anchor in readme or en_anchor in readme:
        if readme.count(zh_anchor)!=1 or readme.count(en_anchor)!=1 or readme.index(zh_anchor)>readme.index(en_anchor):
            return errors+['README.md: missing, duplicate or incorrectly ordered language anchors'],count
        for link in ('](#zh-cn)','](#english)'):
            if link not in readme[:readme.index(zh_anchor)]:errors.append('README.md: language navigation missing '+link)
        sections=[('README.md (zh-CN)','zh-CN',readme.split(zh_anchor,1)[1].split(en_anchor,1)[0]),
                  ('README.md (en)','en',readme.split(en_anchor,1)[1])]
        if not (root/'README.zh-CN.md').is_file():errors.append('README.zh-CN.md: missing compatibility link')
        elif 'README.md#zh-cn' not in (root/'README.zh-CN.md').read_text():errors.append('README.zh-CN.md: Chinese anchor link missing')
    else:
        sections=[]
        for name,language in [('README.md','en'),('README.zh-CN.md','zh-CN')]:
            path=root/name
            if not path.is_file():errors.append(name+': missing README');continue
            source=path.read_text()
            for other in ('README.md','README.zh-CN.md'):
                if ']('+other+')' not in source:errors.append(name+': relative language link missing '+other)
            sections.append((name,language,source))
    for name,language,source in sections:
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
