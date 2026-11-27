#!/usr/bin/env python3
"""Static release guard for first-run identity, branding and bundled artifacts."""
from __future__ import annotations

import hashlib
import json
import plistlib
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {'zh-CN', 'en', 'ja', 'ko', 'ru', 'es', 'de', 'fr', 'pt-BR', 'zh-TW'}
INTERNAL_UI_NAMES = ('HD2FXNative', 'helldivers2-fx-launcher', 'fix/first-run-ssh-access')
PRODUCTION = ('App', 'Core', 'Models', 'Services', 'Stores', 'Views', 'Support')


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def main() -> int:
    errors: list[str] = []
    catalog = json.loads((ROOT / 'Resources/native-locales.json').read_text())
    if set(catalog) != LANGUAGES:
        fail(errors, 'localization language set changed')
    for language, entries in catalog.items():
        for key, value in entries.items():
            if 'FEX' in value:
                fail(errors, f'{language}/{key}: user-visible FEX')
            for internal in INTERNAL_UI_NAMES:
                if internal.lower() in value.lower():
                    fail(errors, f'{language}/{key}: internal project name')

    source_files = [path for folder in PRODUCTION for path in (ROOT / folder).rglob('*.swift')]
    source = '\n'.join(path.read_text(errors='replace') for path in source_files)
    if re.search(r'7656119\d{10}', source):
        fail(errors, 'production source contains a literal SteamID64')
    if re.search(r'(?i)\b(?:uid|gid)\s*[=:]\s*(?:1000|501)\b', source):
        fail(errors, 'production source contains a fixed UID/GID')
    if re.search(r'/Users/(?!<|\\\(|\[)[A-Za-z0-9._-]+/', source):
        fail(errors, 'production source contains a personal macOS path')
    for marker in ('FEX_MISSING', 'FEX_ROOTFS'):
        if marker not in source:
            fail(errors, f'technical marker was incorrectly removed: {marker}')
    adapter = (ROOT / 'Core/ComponentDeploymentAdapters.swift').read_text()
    repair = adapter.split('static func repair(', 1)[-1].split('static let pipeline', 1)[0]
    app_state = (ROOT / 'Stores/AppState.swift').read_text()
    if 'first_run_fex_repair' not in app_state or 'FEX_MISSING' not in app_state:
        fail(errors, 'FEX_MISSING does not enter automatic first-run repair')
    if 'first_run_fex_build' in repair:
        fail(errors, 'automatic repair treats an unapproved source build as a verified download')
    if '#if DEBUG' in adapter or 'FEXBuildApprovals' in source or '--hd2-local-rf-replay' in source:
        fail(errors, 'build configurations must share the same component installer')
    if 'bundleReplay(backend:' not in repair or 'verified-download' not in adapter:
        fail(errors, 'first run must consume the verified Bundle and signed release fallback')

    plist = plistlib.loads((ROOT / 'Info.plist').read_bytes())
    project = (ROOT / 'HD2FXNative.xcodeproj/project.pbxproj').read_text()
    expected_id = 'com.lsjop.helldivers2fx.native.phase1'
    if plist.get('CFBundleIdentifier') != '$(PRODUCT_BUNDLE_IDENTIFIER)':
        fail(errors, 'Info.plist no longer uses the stable bundle identifier setting')
    if project.count('PRODUCT_BUNDLE_IDENTIFIER = "' + expected_id + '";') != 2:
        fail(errors, 'Debug/Release bundle identifier compatibility changed')
    if 'stage_deployment_resources.sh' not in project or 'HD2_PRIVATE_RF_DEBUG' in project:
        fail(errors, 'component assembly is not shared by Debug and Release')

    manifest = json.loads((ROOT / 'Resources/deployment-components-v1.json').read_text())
    for item in manifest.get('bundled', []):
        if item.get('bundled') is not True:
            continue
        path = ROOT / 'Resources' / item['name']
        if not path.is_file():
            fail(errors, 'missing declared Bundle resource: ' + item['name'])
            continue
        data = path.read_bytes()
        if len(data) != item.get('bytes') or hashlib.sha256(data).hexdigest() != item.get('sha256'):
            fail(errors, 'Bundle resource integrity mismatch: ' + item['name'])
    bundle_root = ROOT / 'Resources/Deployment/RF-FEX'
    claimed_rf = [item for item in manifest.get('localTestOnly', []) if item.get('bundled') is True]
    if claimed_rf:
        for item in claimed_rf:
            path = bundle_root / item['name']
            if not path.is_file():
                fail(errors, 'missing declared RF Bundle file: ' + item['name'])
            elif path.stat().st_size != item['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
                fail(errors, 'RF Bundle integrity mismatch: ' + item['name'])
    elif bundle_root.exists() and any(bundle_root.rglob('*')):
        fail(errors, 'unmanifested RF Bundle payload is present')
    plan = manifest.get('rfPackagingPlan', {})
    if plan.get('preferred') != 'APP_BUNDLE' or plan.get('fallback') != 'VERIFIED_DOWNLOAD':
        fail(errors, 'RF packaging priority changed')
    if manifest.get('status') == 'BLOCKED_PUBLIC_RF_DISTRIBUTION' and claimed_rf:
        fail(errors, 'blocked RF payload must not be included in a public Bundle')

    package_manifest_path = ROOT / 'Resources/rf-fex-package-v1.json'
    package = json.loads(package_manifest_path.read_text())
    if hashlib.sha256(package_manifest_path.read_bytes()).hexdigest() not in adapter:
        fail(errors, 'runtime does not pin the shipped RF manifest bytes')
    if len(package['files']) != package['expectedFiles']:
        fail(errors, 'shipped RF inventory count differs')
    if any('distribution' in key.lower() or 'debug' in key.lower() for key in package):
        fail(errors, 'rights and build policies belong outside the runtime manifest')
    guest_tree = {}
    for item in package['files']:
        path = Path(item['path'])
        if path.is_absolute() or '..' in path.parts or item['path'] in guest_tree:
            fail(errors, 'unsafe or duplicate RF package path')
        guest_tree[item['path']] = ['file', item['sha256'], item['mode']]
        for parent in path.parents:
            if parent != Path('.'):
                guest_tree[parent.as_posix()] = ['dir']
    tree_hash = hashlib.sha256(json.dumps(guest_tree, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if tree_hash not in adapter:
        fail(errors, 'managed RF recognition differs from the shipped file inventory')

    if errors:
        print('\n'.join('FAIL ' + error for error in errors))
        return 1
    print('PASS: ten-language FX branding and internal technical markers')
    print('PASS: no literal SteamID, fixed UID/GID or personal production path')
    print('PASS: stable Bundle ID and all declared Bundle resource hashes')
    print('PASS: FEX_MISSING enters repair without approving a non-reproducible source build')
    print('PASS: shared build phase, signed fallback and pinned managed RF inventory')
    return 0


if __name__ == '__main__':
    sys.exit(main())
