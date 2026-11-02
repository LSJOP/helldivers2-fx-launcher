#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HD2FXNative"
BUNDLE_ID="com.lsjop.helldivers2fx.native.phase1"
APP_BUNDLE="$ROOT_DIR/build/Debug/$APP_NAME.app"
case "$MODE" in run|--verify|--build-only|--xcode-only|--debug|--logs|--telemetry|--smoke) ;; *) echo "usage: $0 [run|--verify|--build-only|--xcode-only|--debug|--logs|--telemetry|--smoke]" >&2; exit 2 ;; esac
mkdir -p "$ROOT_DIR/build" "$ROOT_DIR/evidence"
# Stop only this exact app binary, never FX/Steam/Python or another checkout.
/usr/bin/pkill -f "^${APP_BUNDLE}/Contents/MacOS/${APP_NAME}([[:space:]]|$)" >/dev/null 2>&1 || true
if /usr/bin/xcodebuild -version >"$ROOT_DIR/evidence/xcode-toolchain.txt" 2>&1; then
    /usr/bin/xcodebuild -project "$ROOT_DIR/HD2FXNative.xcodeproj" -scheme HD2FXNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$ROOT_DIR/build/DerivedData" CONFIGURATION_BUILD_DIR="$ROOT_DIR/build/Debug" CODE_SIGNING_ALLOWED=NO build >"$ROOT_DIR/evidence/xcode-debug.txt" 2>&1
    echo "Xcode Debug build completed: $APP_BUNDLE"
else
    echo "Complete Xcode is required to resolve and embed Sparkle. No standalone Swift fallback is available." >&2
    exit 69
fi
case "$MODE" in
 --build-only|--xcode-only) ;;
 --debug) /usr/bin/lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
 --smoke) /usr/bin/python3 -I -B "$ROOT_DIR/script/capture_smoke.py" "$APP_BUNDLE" "$ROOT_DIR/evidence/gui" ;;
 --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; /usr/bin/pgrep -f "^${APP_BUNDLE}/Contents/MacOS/${APP_NAME}([[:space:]]|$)" ;;
 --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "HD2FXNative"' ;;
 --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.lsjop.helldivers2fx.native.phase1"' ;;
 run) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
