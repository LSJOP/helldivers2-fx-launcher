#!/usr/bin/env bash
# Explicit operator-only preparation. Never publishes a Release or changes Pages.
set -euo pipefail
if [[ $# != 9 ]]; then
    echo "usage: $0 VERSION BUILD stable|preview TEAM_ID 'Developer ID Application: …' NOTARY_PROFILE NOTES.md NEW_STAGING_DIR EXISTING_APPCAST" >&2
    exit 2
fi
RELEASE_VERSION="$1"; RELEASE_BUILD="$2"; CHANNEL="$3"; TEAM="$4"; IDENTITY="$5"
NOTARY_PROFILE="$6"; NOTES="$7"; STAGING="$8"; EXISTING_FEED="$9"
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
(cd "$APP_ROOT/.." && /usr/bin/python3 -I -B "$APP_ROOT/script/check_release_secrets.py" --tracked)
[[ "$CHANNEL" == stable || "$CHANNEL" == preview ]] || exit 2
[[ "$IDENTITY" == 'Developer ID Application: '* ]] || { echo 'Developer ID Application identity required' >&2; exit 2; }
[[ -f "$NOTES" && -f "$EXISTING_FEED" && ! -e "$STAGING" ]] || { echo 'Notes/feed required; staging must not already exist' >&2; exit 2; }
/usr/bin/python3 - "$RELEASE_VERSION" "$RELEASE_BUILD" "$CHANNEL" <<'PY'
import re,sys
version,build,channel=sys.argv[1:]
assert re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?',version), 'Semantic version required'
assert re.fullmatch(r'[1-9]\d*',build), 'Monotonically increasing positive build required'
assert (channel=='preview') == ('-' in version), 'Preview needs prerelease version; stable needs final version'
PY
mkdir -p "$STAGING"
STAGING="$(cd "$STAGING" && pwd)"
# Freeze caller-owned history: later edits must not change what we verify/reuse.
HISTORY="$STAGING/previous-appcast.xml"
cp "$EXISTING_FEED" "$HISTORY"
xcodebuild -project "$APP_ROOT/HD2FXNative.xcodeproj" -scheme HD2FXNative -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$STAGING/Launcher.xcarchive" \
    -derivedDataPath "$STAGING/DerivedData" \
    MARKETING_VERSION="$RELEASE_VERSION" CURRENT_PROJECT_VERSION="$RELEASE_BUILD" \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGNING_ALLOWED=YES \
    ENABLE_HARDENED_RUNTIME=YES HD2_UPDATE_CHANNEL=stable HD2_UPDATE_DISTRIBUTION_READY=YES archive
APP="$STAGING/Launcher.xcarchive/Products/Applications/HD2FXNative.app"
/usr/bin/python3 - "$APP/Contents/Info.plist" "$CHANNEL" "$RELEASE_VERSION" "$RELEASE_BUILD" <<'PY'
import base64,plistlib,sys
with open(sys.argv[1],'rb') as f:p=plistlib.load(f)
assert p['CFBundleIdentifier']=='com.lsjop.helldivers2fx.native.phase1'
assert p['CFBundleShortVersionString']==sys.argv[3] and p['CFBundleVersion']==sys.argv[4]
assert p['HD2UpdateServiceEnabled']=='YES', 'Configure the actual public feed and EdDSA public key first'
assert p['SUFeedURL']=='https://lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml'
assert p['HD2UpdateDistributionReady']=='YES'
assert p['SUAllowsAutomaticUpdates'] is False and p['SUSignedFeedFailureExpirationInterval']==0
assert len(base64.b64decode(p['SUPublicEDKey'],validate=True))==32
PY
codesign --verify --deep --strict "$APP"
/usr/bin/python3 -I -B "$APP_ROOT/script/check_release_secrets.py" --path "$APP"
codesign -dv "$APP" 2>&1 | /usr/bin/grep -F 'Authority=Developer ID Application:' >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING/notary-submission.zip"
xcrun notarytool submit "$STAGING/notary-submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"
ARCHIVES="$STAGING/updates"
mkdir "$ARCHIVES"
ARCHIVE_NAME="HD2FXLauncher-${RELEASE_VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVES/$ARCHIVE_NAME"
/usr/bin/python3 -I -B "$APP_ROOT/script/check_release_secrets.py" --archive "$ARCHIVES/$ARCHIVE_NAME"
cp "$NOTES" "$ARCHIVES/${ARCHIVE_NAME%.zip}.md"
TOOLS="$STAGING/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
# Default Sparkle Keychain account only. No private key argument, file or export.
PUBLIC_KEY="$("$TOOLS/generate_keys" -p)"
/usr/bin/python3 - "$APP/Contents/Info.plist" "$PUBLIC_KEY" <<'PY'
import plistlib,sys
with open(sys.argv[1],'rb') as f:p=plistlib.load(f)
assert p['SUPublicEDKey']==sys.argv[2].strip(), 'Keychain key does not match the bundled public key'
assert p['SURequireSignedFeed'] is True and p['SUVerifyUpdateBeforeExtraction'] is True
PY
# Never re-sign unverified history into a trusted update feed.
"$TOOLS/sign_update" --verify "$HISTORY"
/usr/bin/python3 -I -B "$APP_ROOT/script/validate_release_history.py" "$HISTORY" "$CHANNEL" "$RELEASE_BUILD"
cp "$HISTORY" "$ARCHIVES/appcast.xml"
SIGNATURE="$("$TOOLS/sign_update" -p "$ARCHIVES/$ARCHIVE_NAME")"
"$TOOLS/sign_update" --verify "$ARCHIVES/$ARCHIVE_NAME" "$SIGNATURE"
/usr/bin/python3 -I -B "$APP_ROOT/script/make_update_manifest.py" "$APP/Contents/Info.plist" "$ARCHIVES/$ARCHIVE_NAME" "$CHANNEL" "$ARCHIVES/native-update.json"
"$TOOLS/sign_update" -p "$ARCHIVES/native-update.json" > "$ARCHIVES/native-update.json.sig"
MANIFEST_SIGNATURE="$(cat "$ARCHIVES/native-update.json.sig")"
"$TOOLS/sign_update" --verify "$ARCHIVES/native-update.json" "$MANIFEST_SIGNATURE"
CHANNEL_ARGS=()
if [[ "$CHANNEL" == preview ]]; then CHANNEL_ARGS=(--channel preview); fi
"$TOOLS/generate_appcast" --maximum-deltas 0 --maximum-versions 10000 --versions "$RELEASE_BUILD" \
    --embed-release-notes --download-url-prefix "https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/native-v${RELEASE_VERSION}/" \
    "${CHANNEL_ARGS[@]}" "$ARCHIVES"
"$TOOLS/sign_update" --verify "$ARCHIVES/appcast.xml"
/usr/bin/python3 -I -B "$APP_ROOT/script/check_release_secrets.py" --path "$ARCHIVES/appcast.xml" --path "$NOTES"
/usr/bin/python3 - "$ARCHIVES/appcast.xml" "$ARCHIVES/$ARCHIVE_NAME" "$RELEASE_BUILD" "$CHANNEL" "$HISTORY" <<'PY'
import base64,pathlib,sys,xml.etree.ElementTree as E
feed,archive,build,channel,previous=sys.argv[1:];ns={'s':'http://www.andymatuschak.org/xml-namespaces/sparkle'}
tree=E.parse(feed);items=tree.findall('./channel/item')
def version(item):
    enclosed=item.find('enclosure');return item.findtext('s:version',namespaces=ns) or (enclosed.get('{'+ns['s']+'}version') if enclosed is not None else None)
old={version(x) for x in E.parse(previous).findall('./channel/item')};new={version(x) for x in items}
assert old<=new, 'Existing feed history was removed; review before publishing'
item=next(x for x in items if version(x)==build);enclosure=item.find('enclosure')
assert enclosure is not None and int(enclosure.get('length'))==pathlib.Path(archive).stat().st_size
assert len(base64.b64decode(enclosure.get('{'+ns['s']+'}edSignature'),validate=True))==64
release_version=pathlib.Path(archive).name.removeprefix('HD2FXLauncher-').removesuffix('.zip')
assert enclosure.get('url')=='https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/native-v'+release_version+'/'+pathlib.Path(archive).name
assert item.findtext('s:channel',namespaces=ns)==('preview' if channel=='preview' else None)
assert build not in old, 'Do not overwrite an existing build'
assert all(x and x.isdigit() and int(build)>int(x) for x in old), 'Build number must increase across feed history'
PY
echo "Prepared signed/notarized Launcher archive and appcast in: $ARCHIVES"
echo 'Nothing published. Review release notes, version/build order, signature and feed before manual publication.'
