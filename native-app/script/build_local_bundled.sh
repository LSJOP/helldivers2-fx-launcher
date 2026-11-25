#!/usr/bin/env bash
# Build a local-only App from an existing, complete set of pinned components.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source_path="${1:?usage: build_local_bundled.sh VERIFIED_ASSET_ROOT_OR_APP NEW_ABSOLUTE_OUTPUT_DIRECTORY}"
output="${2:?usage: build_local_bundled.sh VERIFIED_ASSET_ROOT_OR_APP NEW_ABSOLUTE_OUTPUT_DIRECTORY}"
[[ "$output" = /* && ! -e "$output" && ! -L "$output" ]] ||
    { echo 'A new absolute output directory is required.' >&2; exit 2; }
[[ -z "${CI:-}" && -z "${GITHUB_ACTIONS:-}" ]] ||
    { echo 'Private payload builds are local only.' >&2; exit 2; }
case "$source_path" in
    *.app|*.app/) source_path="${source_path%/}/Contents/Resources" ;;
esac
source_root="$(cd "$source_path" && pwd -P)"
manifest="$root/Resources/rf-fex-debug-manifest-v1.json"
catalogue="$root/Resources/deployment-components-v1.json"

/usr/bin/python3 -I -B "$root/script/rf_fex_bundle.py" verify \
    --manifest "$manifest" --payload "$source_root/Deployment/RF-FEX"
/usr/bin/python3 -I -B "$root/script/deployment_archives.py" verify \
    --catalogue "$catalogue" --destination "$source_root"

mkdir "$output"
output="$(cd "$output" && pwd -P)"
/usr/bin/xcodebuild -project "$root/HD2FXNative.xcodeproj" -scheme HD2FXNative \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$output/DerivedData" CONFIGURATION_BUILD_DIR="$output/Products" \
    CODE_SIGNING_ALLOWED=NO HD2_PRIVATE_RF_DEBUG=YES HD2_PRIVATE_CORE_DEBUG=YES \
    HD2_UPDATE_ENABLED=NO HD2_UPDATE_DISTRIBUTION_READY=NO \
    HD2_PRIVATE_RESOURCES_ROOT="$source_root" build > "$output/build.log" 2>&1

app="$output/Products/HD2FXNative.app"
resources="$app/Contents/Resources"
/usr/bin/cmp "$manifest" "$resources/Deployment/RF-FEX.manifest.json"
/usr/bin/python3 -I -B "$root/script/rf_fex_bundle.py" verify \
    --manifest "$manifest" --payload "$resources/Deployment/RF-FEX"
/usr/bin/python3 -I -B "$root/script/deployment_archives.py" verify \
    --catalogue "$catalogue" --destination "$resources"
/usr/bin/codesign --force --deep --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
printf '%s\n' 'Trusted / Bundled (local only): RF FEX, Proton-JE, SteamLinuxRuntime_4' "$app"
