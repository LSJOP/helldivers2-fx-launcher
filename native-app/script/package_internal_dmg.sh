#!/usr/bin/env bash
# Build and test an internal installer from a clean Git snapshot.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:?usage: package_internal_dmg.sh NEW_ABSOLUTE_OUTPUT_DIR [VERSION] [BUILD]}"
version="${2:-1.0.0}"
build="${3:-$(date -u +%Y%m%d%H%M%S)}"
[[ "$output" = /* && "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[1-9][0-9]*$ ]]
[[ -z "$(git -C "$root" status --porcelain)" ]] || { echo 'Build from a clean Git snapshot.' >&2; exit 2; }

mkdir "$output"
report="$output/RELEASE-REPORT.txt"
mount_point=""
app_pid=""
finish() {
    local result=$?
    if [[ -n "$app_pid" ]]; then kill -TERM "$app_pid" 2>/dev/null || true; fi
    if [[ -n "$mount_point" ]]; then hdiutil detach "$mount_point" >> "$output/install-test.log" 2>&1 || true; fi
    printf 'Automated build and install exit status: %s\n' "$result" >> "$report"
}
trap finish EXIT
log() { printf '%s\n' "$*" | tee -a "$report"; }

identity_list="$(security find-identity -v -p codesigning)"
identity="$(printf '%s\n' "$identity_list" | awk '/"Developer ID Application:/ && !seen++ {print $2}')"
log "Internal test only | Version $version ($build) | arm64"
log "Source: $(git -C "$root" rev-parse HEAD)"
log 'Guest acceptance pending: first-run configuration, FX, SteamOS, SSH and sudo.'
log 'Stable release acceptance pending: game launch, EAC and multiplayer.'
sign_settings=(CODE_SIGNING_ALLOWED=NO)
if [[ -n "$identity" ]]; then
    log 'Signing: Developer ID Application'
    sign_settings=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity")
else
    log 'Signing: ad hoc (internal testing only)'
fi

package_settings=()
if [[ -n "${HD2_PACKAGE_CACHE:-}" ]]; then
    package_settings=(-clonedSourcePackagesDirPath "$HD2_PACKAGE_CACHE" -disableAutomaticPackageResolution)
fi
xcodebuild -project "$root/HD2FXNative.xcodeproj" -scheme HD2FXNative \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$output/DerivedData" CONFIGURATION_BUILD_DIR="$output/Products" \
    "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build" \
    HD2_UPDATE_DISTRIBUTION_READY=NO HD2_UPDATE_ENABLED=NO \
    "${package_settings[@]}" "${sign_settings[@]}" build > "$output/build.log" 2>&1
app="$output/Products/HD2FXNative.app"
if [[ -z "$identity" ]]; then codesign --force --deep --sign - "$app"; fi
codesign -dv --verbose=4 "$app" > "$output/signature.log" 2>&1
if [[ -n "$identity" ]]; then
    grep -q '^Authority=Developer ID Application:' "$output/signature.log"
fi

check_app() {
    local bundle="$1" executable="$1/Contents/MacOS/HD2FXNative" plist="$1/Contents/Info.plist"
    "$root/script/check_release_bundle.sh" "$bundle"
    /usr/bin/python3 -I -B "$root/script/check_release_secrets.py" --path "$bundle"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$version" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "$build" ]]
    for framework in SwiftUI AppKit; do
        otool -L "$executable" | grep "/$framework.framework/" >/dev/null
    done
    if find "$bundle" \( -name '*.dSYM' -o -name '*.swift' -o -name '*.log' -o -name '*.xcdebugger' \) -print | grep .; then
        echo 'Unexpected development files in the app bundle.' >&2
        return 1
    fi
}
check_app "$app" > "$output/bundle-validation.log" 2>&1
log 'Release bundle verified. Native Swift Core is bundled. Python Core files are excluded.'

mkdir "$output/image-content" "$output/Installed"
ditto "$app" "$output/image-content/HD2FXNative.app"
ln -s /Applications "$output/image-content/Applications"
dmg="$output/HD2-FX-Launcher-v$version-arm64.dmg"
hdiutil create -srcfolder "$output/image-content" -volname 'HD2 FX Launcher' \
    -format UDZO -ov "$dmg" > "$output/image.log" 2>&1
if [[ -n "$identity" ]]; then
    codesign --sign "$identity" --timestamp "$dmg"
    if [[ -n "${HD2_NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$dmg" --keychain-profile "$HD2_NOTARY_PROFILE" --wait > "$output/notary.log"
        xcrun stapler staple "$dmg"
        xcrun stapler validate "$dmg"
        log 'Apple notarization and stapling verified.'
    else
        log 'Apple notarization skipped (no HD2_NOTARY_PROFILE).'
    fi
else
    log 'Apple notarization unavailable for ad hoc signing.'
fi
(cd "$output" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
(cd "$output" && shasum -a 256 -c "$(basename "$dmg").sha256") >> "$output/install-test.log"
hdiutil verify "$dmg" >> "$output/install-test.log" 2>&1

mkdir "$output/mount"
hdiutil attach -readonly -nobrowse -mountpoint "$output/mount" "$dmg" >> "$output/install-test.log" 2>&1
mount_point="$output/mount"
[[ "$(readlink "$mount_point/Applications")" = /Applications ]]
installed="$output/Installed/HD2FXNative.app"
ditto "$mount_point/HD2FXNative.app" "$installed"
check_app "$installed" >> "$output/install-test.log" 2>&1
hdiutil detach "$mount_point" >> "$output/install-test.log" 2>&1
mount_point=""
log 'DMG checksum, mount, Applications link, install copy, signature and executable resources verified.'

# Launch the installed copy after unmounting. A fresh instance distinguishes it
# from any existing launcher. Check its full executable path, not just its name.
open -n "$installed"
sleep 5
app_pid="$(ps -axo pid=,command= | awk -v app="$installed/Contents/MacOS/HD2FXNative" '
    { pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0==app) print pid }
')"
[[ "$app_pid" =~ ^[0-9]+$ ]]
kill -0 "$app_pid"
log 'Installed Release process started from the independent copy after DMG detach.'
log "Installer: $dmg"
