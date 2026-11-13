#!/usr/bin/env python3
"""Generate public metadata for an already built and signed Native archive.

No signing keys and no publication. Sign the exact resulting bytes with Sparkle.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import re

BUNDLE = 'com.lsjop.helldivers2fx.native.phase1'

def manifest(info, archive, channel, architecture):
    version=info.get('CFBundleShortVersionString','')
    build=info.get('CFBundleVersion','')
    assert info.get('CFBundleIdentifier')==BUNDLE, 'Wrong application identity'
    assert re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?',version), 'Invalid version'
    assert re.fullmatch(r'[1-9]\d*',build), 'Invalid build'
    assert channel in ('stable','preview') and (channel=='preview')==('-' in version), 'Channel/version mismatch'
    assert architecture in ('arm64','universal'), 'Unsupported architecture'
    assert archive.name=='HD2FXLauncher-'+version+'.zip' and archive.is_file() and not archive.is_symlink(), 'Wrong archive'
    size=archive.stat().st_size
    assert 0<size<=536870912, 'Archive size outside supported limit'
    minimum=info.get('LSMinimumSystemVersion','')
    assert re.fullmatch(r'\d+\.\d+(?:\.\d+)?',minimum), 'Missing minimum macOS version'
    sha=hashlib.sha256()
    with archive.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1048576),b''):sha.update(chunk)
    return dict(schema=1,bundleID=BUNDLE,version=version,build=int(build),channel=channel,platform='macOS',architecture=architecture,
                minimumSystemVersion=minimum,archive=archive.name,length=size,sha256=sha.hexdigest())

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('info',type=Path);parser.add_argument('archive',type=Path);parser.add_argument('channel',choices=['stable','preview'])
    parser.add_argument('output',type=Path);parser.add_argument('--architecture',default='arm64',choices=['arm64','universal'])
    parser.add_argument('--archive-signature',type=Path)
    args=parser.parse_args()
    value=manifest(plistlib.loads(args.info.read_bytes()),args.archive,args.channel,args.architecture)
    if args.archive_signature:
        signature=args.archive_signature.read_text().strip()
        assert len(base64.b64decode(signature,validate=True))==64, 'Invalid archive Ed25519 signature'
        value.update(schema=2,archiveEdSignature=signature)
    with args.output.open('x',encoding='utf-8') as stream:stream.write(json.dumps(value,sort_keys=True,separators=(',',':'))+'\n')
if __name__=='__main__':main()
