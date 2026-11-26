#!/usr/bin/env bash
# Assemble a local v1.0.7 review candidate from a clean Release App.
# This does not publish, tag, or authorize a Stable release.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="${1:?usage: assemble_component_release_candidate.sh SOURCE_APP NEW_OUTPUT_DIRECTORY}"
OUTPUT="${2:?usage: assemble_component_release_candidate.sh SOURCE_APP NEW_OUTPUT_DIRECTORY}"
[[ "$SOURCE_APP" = /* && "$OUTPUT" = /* && ! -e "$OUTPUT" ]] || {
  echo "Absolute source and new output directory are required" >&2
  exit 2
}
[[ -d "$SOURCE_APP" && "$SOURCE_APP" = *.app ]] || { echo "Release App is missing" >&2; exit 2; }
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "Clean committed source is required" >&2; exit 2; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")"
CONFIGURATION="$(/usr/bin/python3 -I -B - "$SOURCE_APP/Contents/Resources/BuildMetadata.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['configuration'])
PY
)"
[[ "$VERSION" == "1.0.7" && "$CONFIGURATION" == "Release" ]] || {
  echo "Expected a v1.0.7 Release App" >&2
  exit 2
}

mkdir "$OUTPUT"
APP="$OUTPUT/HD2FXNative.app"
/usr/bin/ditto "$SOURCE_APP" "$APP"
DEPLOYMENT="$APP/Contents/Resources/Deployment"
mkdir -p "$DEPLOYMENT"

/usr/bin/python3 -I -B "$ROOT/script/rf_fex_bundle.py" assemble-release \
  --manifest "$ROOT/Resources/rf-fex-debug-manifest-v1.json" \
  --approval "$ROOT/Resources/distribution-approvals-v1.json" \
  --resources "$ROOT/Resources" \
  --payload "$ROOT/PrivateResources/Deployment/RF-FEX" \
  --destination "$DEPLOYMENT/RF-FEX" \
  --output-manifest "$DEPLOYMENT/RF-FEX.manifest.json"

/usr/bin/python3 -I -B "$ROOT/script/deployment_archives.py" copy \
  --catalogue "$ROOT/Resources/deployment-components-v1.json" \
  --source "$ROOT/PrivateResources" \
  --destination "$APP/Contents/Resources"

/bin/cp "$ROOT/../THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
/usr/bin/codesign --force --deep --sign - "$APP"

/usr/bin/python3 -I -B "$ROOT/script/rf_fex_bundle.py" verify-release \
  --manifest "$DEPLOYMENT/RF-FEX.manifest.json" \
  --approval "$ROOT/Resources/distribution-approvals-v1.json" \
  --payload "$DEPLOYMENT/RF-FEX"
/usr/bin/python3 -I -B "$ROOT/script/deployment_archives.py" verify \
  --catalogue "$ROOT/Resources/deployment-components-v1.json" \
  --destination "$APP/Contents/Resources"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/shasum -a 256 "$APP/Contents/MacOS/HD2FXNative" > "$OUTPUT/executable-sha256.txt"
echo "$APP"
