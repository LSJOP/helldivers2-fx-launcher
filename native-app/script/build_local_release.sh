#!/usr/bin/env bash
# Optimized local Release, ad hoc signed. No distribution/notarization claim.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:?usage: build_local_release.sh <new-absolute-output-directory>}"
[[ "$OUTPUT_DIR" = /* ]] || { echo 'Absolute output directory required' >&2; exit 2; }
[[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ]] || { echo 'Clean committed snapshot required' >&2; exit 2; }
mkdir "$OUTPUT_DIR" # Never reuse another build or its DerivedData.
git -C "$ROOT_DIR" rev-parse HEAD > "$OUTPUT_DIR/SOURCE-COMMIT.txt"
/usr/bin/xcodebuild -project "$ROOT_DIR/HD2FXNative.xcodeproj" -scheme HD2FXNative \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$OUTPUT_DIR/DerivedData" CONFIGURATION_BUILD_DIR="$OUTPUT_DIR/Products" \
  CODE_SIGNING_ALLOWED=NO build > "$OUTPUT_DIR/release-build.txt" 2>&1
APP="$OUTPUT_DIR/Products/HD2FXNative.app"
# No credentials, entitlements, or hardened-runtime exceptions are invented here.
# Formal Developer ID distribution remains a separate workflow.
/usr/bin/codesign --force --deep --sign - "$APP" > "$OUTPUT_DIR/signing.txt" 2>&1
"$ROOT_DIR/script/check_release_bundle.sh" "$APP" > "$OUTPUT_DIR/release-validation.txt" 2>&1
/usr/bin/shasum -a 256 "$APP/Contents/MacOS/HD2FXNative" > "$OUTPUT_DIR/executable-sha256.txt"
echo "$APP"
