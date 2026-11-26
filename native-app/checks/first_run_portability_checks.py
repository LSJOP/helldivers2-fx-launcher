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
    for marker in ('FEX_MISSING', 'FEXBash', 'FEX_ROOTFS'):
        if marker not in source:
            fail(errors, f'technical marker was incorrectly removed: {marker}')
    adapter = (ROOT / 'Core/ComponentDeploymentAdapters.swift').read_text()
    repair = adapter.split('static func repair(', 1)[-1].split('static let pipeline', 1)[0]
    app_state = (ROOT / 'Stores/AppState.swift').read_text()
    if 'first_run_fex_repair' not in app_state or 'FEX_MISSING' not in app_state:
        fail(errors, 'FEX_MISSING does not enter automatic first-run repair')
    if 'first_run_fex_build' in repair:
        fail(errors, 'automatic repair treats an unapproved source build as a verified download')
    if 'RF_BUNDLE_PAYLOAD_UNAVAILABLE' not in repair or 'BLOCKED_PUBLIC_RF_DISTRIBUTION' not in repair:
        fail(errors, 'automatic repair does not preserve the RF distribution blocker')
    if 'bundleReplay(backend:' not in repair or 'resource_source' not in adapter:
        fail(errors, 'automatic repair does not consume the verified App Bundle payload')

    plist = plistlib.loads((ROOT / 'Info.plist').read_bytes())
    project = (ROOT / 'HD2FXNative.xcodeproj/project.pbxproj').read_text()
    expected_id = 'com.lsjop.helldivers2fx.native.phase1'
    if plist.get('CFBundleIdentifier') != '$(PRODUCT_BUNDLE_IDENTIFIER)':
        fail(errors, 'Info.plist no longer uses the stable bundle identifier setting')
    if project.count('PRODUCT_BUNDLE_IDENTIFIER = "' + expected_id + '";') != 2:
        fail(errors, 'Debug/Release bundle identifier compatibility changed')
    for marker in ('PrivateResources/Deployment/RF-FEX', 'RF-FEX.manifest.json',
                   'Unapproved RF payload in Release resources'):
        if marker not in project:
            fail(errors, 'Debug/Release RF resource gate missing: ' + marker)

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

    debug_manifest_path = ROOT / 'Resources/rf-fex-debug-manifest-v1.json'
    debug_manifest = json.loads(debug_manifest_path.read_text())
    if hashlib.sha256(debug_manifest_path.read_bytes()).hexdigest() not in adapter:
        fail(errors, 'runtime does not pin the controlled-Debug manifest bytes')
    debug_files = debug_manifest.get('files', [])
    debug_paths = [item.get('path') for item in debug_files]
    if (debug_manifest.get('schema') != 1 or debug_manifest.get('expectedFiles') != 41
            or len(debug_files) != 41 or len(set(debug_paths)) != 41
            or debug_manifest.get('debugOnly') is not True
            or debug_manifest.get('distributionApproved') is not False):
        fail(errors, 'controlled-Debug RF manifest policy or inventory is invalid')
    guest_tree = {}
    for item in debug_files:
        path = item.get('path', '')
        if (not path or path.startswith('/') or '..' in Path(path).parts or '\\' in path
                or item.get('mode') not in (0o644, 0o755)
                or not re.fullmatch(r'[a-f0-9]{64}', item.get('sha256', ''))
                or item.get('publicDistributionAllowed') is not False
                or item.get('controlledDebugOnly') is not True):
            fail(errors, 'invalid controlled-Debug RF entry: ' + repr(path))
            continue
        guest_tree[path] = ['file', item['sha256'], item['mode']]
        for parent in Path(path).parents:
            if parent != Path('.'):
                guest_tree[parent.as_posix()] = ['dir']
    tree_hash = hashlib.sha256(json.dumps(guest_tree, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if tree_hash not in adapter:
        fail(errors, 'managed repair tree differs from the 41-file manifest')
    plan = manifest.get('rfPackagingPlan', {})
    if (plan.get('debugExpectedFiles') != 41
            or plan.get('debugPayloadFingerprint') != debug_manifest.get('payloadFingerprint')
            or plan.get('releaseBuildGate') != 'ALLOW_HASH_BOUND_RC_ONLY_REJECT_STABLE_UNTIL_ACCEPTED'
            or plan.get('releaseExpectedFiles') != 41
            or plan.get('releasePayloadFingerprint') != '79c051c4e5523513dcb5e030ac466f9b3941551e4f3109132e775b886596fbcd'):
        fail(errors, 'component catalogue and controlled-Debug RF manifest disagree')

    if errors:
        print('\n'.join('FAIL ' + error for error in errors))
        return 1
    print('PASS: ten-language FX branding and internal technical markers')
    print('PASS: no literal SteamID, fixed UID/GID or personal production path')
    print('PASS: stable Bundle ID and all declared Bundle resource hashes')
    print('PASS: FEX_MISSING enters repair without approving a non-reproducible source build')
    print('PASS: 41-file controlled-Debug RF manifest and Release isolation gate')
    if claimed_rf:
        print(f'PASS: {len(claimed_rf)} RF Bundle files match the approved manifest')
    else:
        print('PASS: RF public Bundle payload remains honestly blocked and absent')
    return 0


if __name__ == '__main__':
    sys.exit(main())
