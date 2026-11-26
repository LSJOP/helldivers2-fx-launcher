#!/usr/bin/env bash
# Package a local, review-only v1.0.7 dual-component candidate.
# This script does not create a tag, publish assets, or sign update metadata.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?usage: package_component_release_candidate.sh APP NEW_OUTPUT_DIRECTORY}"
OUTPUT="${2:?usage: package_component_release_candidate.sh APP NEW_OUTPUT_DIRECTORY}"
[[ "$APP" = /* && "$OUTPUT" = /* && ! -e "$OUTPUT" ]] || {
  echo "Absolute App and new output directory are required" >&2
  exit 2
}
[[ -d "$APP" && "$APP" = *.app ]] || { echo "Candidate App is missing" >&2; exit 2; }
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "Clean committed source is required" >&2; exit 2; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
[[ "$VERSION" == "1.0.7" && "$BUILD" == "2026112602" ]] || { echo "Unexpected candidate version" >&2; exit 2; }
[[ "$BUNDLE_ID" == "com.lsjop.helldivers2fx.native.phase1" ]] || { echo "Unexpected Bundle Identifier" >&2; exit 2; }
[[ ! -e "$APP/Contents/Resources/Deployment/SteamLinuxRuntime_4" ]] || { echo "Runtime 4 must remain Steam-managed" >&2; exit 2; }

/usr/bin/python3 -I -B "$ROOT/script/rf_fex_bundle.py" verify-release \
  --manifest "$APP/Contents/Resources/Deployment/RF-FEX.manifest.json" \
  --approval "$ROOT/Resources/distribution-approvals-v1.json" \
  --payload "$APP/Contents/Resources/Deployment/RF-FEX"
/usr/bin/python3 -I -B "$ROOT/script/deployment_archives.py" verify \
  --catalogue "$ROOT/Resources/deployment-components-v1.json" \
  --destination "$APP/Contents/Resources"
/usr/bin/codesign --verify --deep --strict "$APP"

mkdir "$OUTPUT"
ZIP="$OUTPUT/HD2-FX-Launcher-v1.0.7-RC-arm64.zip"
DMG="$OUTPUT/HD2-FX-Launcher-v1.0.7-RC-arm64.dmg"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP" "$ZIP"

PREFLIGHT="$OUTPUT/zip-preflight"
/usr/bin/xcrun swiftc "$ROOT/UpdateHelper/ArchivePathPolicy.swift" \
  "$ROOT/UpdateHelper/UpdateZIPPreflight.swift" \
  "$ROOT/Services/UpdateReleaseService.swift" \
  -o "$PREFLIGHT"
"$PREFLIGHT" "$ZIP"

/usr/bin/hdiutil create -quiet -fs HFS+ -format UDZO -imagekey zlib-level=9 \
  -volname "HD2 FX Launcher v1.0.7 RC" -srcfolder "$APP" "$DMG"
/usr/bin/codesign --verify --deep --strict "$APP" > "$OUTPUT/code-signature-verification.txt" 2>&1
/usr/bin/shasum -a 256 "$DMG" "$ZIP" > "$OUTPUT/SHA256SUMS"
/usr/bin/stat -f '%N %z bytes' "$DMG" "$ZIP" > "$OUTPUT/SIZES.txt"
/usr/bin/du -sk "$APP" > "$OUTPUT/APP-SIZE-KIB.txt"
rm -f "$PREFLIGHT"
printf '%s\n' "$DMG" "$ZIP"
