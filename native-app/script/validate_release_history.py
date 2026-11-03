#!/usr/bin/env python3
"""Policy checks after official Sparkle signature verification; never signs."""
import base64
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
PREFIX = 'https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/native-v'


def validate(path, channel, next_build):
    if channel not in ('stable', 'preview') or not re.fullmatch(r'[1-9]\d*', next_build):
        raise ValueError('Invalid channel or next build')
    data = Path(path).read_bytes()
    if len(data) > 8 * 1024 * 1024 or b'<!DOCTYPE' in data.upper() or b'<!ENTITY' in data.upper():
        raise ValueError('Unsupported feed size or XML declaration')
    root = ET.fromstring(data)
    if root.tag != 'rss' or len(root.findall('channel')) != 1:
        raise ValueError('Expected one RSS channel')
    seen = set()
    for item in root.findall('./channel/item'):
        enclosures = item.findall('enclosure')
        if len(enclosures) != 1:
            raise ValueError('Expected one application archive')
        enclosure = enclosures[0]
        build = item.findtext(SPARKLE + 'version') or enclosure.get(SPARKLE + 'version', '')
        version = item.findtext(SPARKLE + 'shortVersionString') or enclosure.get(SPARKLE + 'shortVersionString', '')
        if not re.fullmatch(r'[1-9]\d*', build) or build in seen or int(build) >= int(next_build):
            raise ValueError('Duplicate, invalid or non-increasing build')
        seen.add(build)
        if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?', version):
            raise ValueError('Missing Native semantic version')
        if (channel == 'preview') != ('-' in version) or item.findtext(SPARKLE + 'channel') != ('preview' if channel == 'preview' else None):
            raise ValueError('History belongs to another release channel')
        expected = PREFIX + version + '/HD2FXLauncher-' + version + '.zip'
        if enclosure.get('url') != expected or enclosure.get(SPARKLE + 'installationType', 'application') != 'application':
            raise ValueError('History archive source or installation type is unsupported')
        length = enclosure.get('length', '')
        if not re.fullmatch(r'[1-9]\d*', length) or int(length) > 536870912:
            raise ValueError('Invalid archive size')
        if len(base64.b64decode(enclosure.get(SPARKLE + 'edSignature', ''), validate=True)) != 64:
            raise ValueError('Missing archive signature')


if __name__ == '__main__':
    validate(*sys.argv[1:])
