#!/usr/bin/env python3
"""Check macOS bundle names and language coverage in source or a built app."""
import argparse
import json
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAMES = {
    'en': 'HELLDIVERS 2 FX Launcher', 'zh-Hans': '绝地潜兵 2 FX 启动器',
    'zh-Hant': '絕地潛兵 2 FX 啟動器',
    **{language: 'HELLDIVERS 2 FX Launcher' for language in ('ja', 'ko', 'ru', 'es', 'de', 'fr', 'pt-BR')},
}

def strings(path):
    # Detect duplicate declarations before the plist parser collapses them.
    content = path.read_bytes()
    try:
        source = content.decode('utf-8')
    except UnicodeDecodeError:
        source = ''  # Compiled binary strings files have already passed source checks.
    if source:
        keys = re.findall(r'^\s*"(CFBundle(?:Name|DisplayName))"\s*=', source, re.M)
        assert sorted(keys) == ['CFBundleDisplayName', 'CFBundleName'], (path, keys)
    converted = subprocess.check_output(['/usr/bin/plutil', '-convert', 'xml1', '-o', '-', str(path)])
    return plistlib.loads(converted)

def check(info, resources):
    assert info['CFBundleDevelopmentRegion'] == 'en'
    assert set(info['CFBundleLocalizations']) == set(NAMES)
    assert info['CFBundleName'] == NAMES['en']
    # Finder localizes only when the unlocalized display name matches the .app filename.
    assert info['CFBundleDisplayName'] == 'HD2FXNative'
    for locale, expected in NAMES.items():
        data = strings(resources / (locale + '.lproj') / 'InfoPlist.strings')
        assert data.get('CFBundleName') == data.get('CFBundleDisplayName') == expected, locale
    print(f'PASS: {len(NAMES)} localizations, English development fallback and nonempty names')

def check_in_app_names():
    # The independently selected App language should show the same brand as the
    # system bundle translation for that language; the two preferences may differ.
    catalog = json.loads((ROOT / 'Resources/native-locales.json').read_text())
    for language, entries in catalog.items():
        locale = {'zh-CN': 'zh-Hans', 'zh-TW': 'zh-Hant'}.get(language, language)
        assert entries.get('ui.brand.name') == NAMES[locale], language
        assert NAMES[locale] in entries.get('ui.art.welcomeTitle', ''), language
        assert 'HD2FXNative' not in entries['ui.art.welcomeTitle'], language
    assert len(catalog) == len(NAMES)
    print(f'PASS: {len(catalog)} in-app brand names match bundle translations')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, help='also check a built .app bundle')
    args = parser.parse_args()
    check(plistlib.loads((ROOT / 'Info.plist').read_bytes()), ROOT / 'Localization')
    check_in_app_names()
    if args.app:
        check(plistlib.loads((args.app / 'Contents/Info.plist').read_bytes()), args.app / 'Contents/Resources')
