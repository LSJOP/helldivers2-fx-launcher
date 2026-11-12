#!/usr/bin/env bash
# Release resource-integrity gate. Verifies an app bundle without launching it.
# Usage: check_release_bundle.sh <path-to-HD2FXNative.app>
set -u
APP="${1:?usage: check_release_bundle.sh <app>}"
GVPROXY_SHA256="27136dd87a6e8c35c2607077a6303082e577751a9e31ebcaa1bd81c93cc58444"
fail=0
ok(){ printf '%s: PASS\n' "$1"; }
bad(){ printf '%s: FAIL\n' "$1"; fail=1; }
has(){ [ -e "$1" ] && ok "$2" || bad "$2"; }

[ -d "$APP" ] || { echo "APP PRESENT: FAIL"; exit 1; }
ok "APP PRESENT"
has "$APP/Contents/Resources/AppIcon.icns" "APP ICON RESOURCE"
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
  /usr/bin/sips -g format "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 && ok "APP ICON FORMAT" || bad "APP ICON FORMAT"
else
  bad "APP ICON FORMAT"
fi
has "$APP/Contents/Resources/Assets.car" "ASSET CATALOG"
has "$APP/Contents/Resources/native-locales.json" "LOCALIZATION CATALOG"
# Ten language lproj directories.
missing_langs=0
for lang in en zh-Hans zh-Hant ja ko ru es de fr pt-BR; do
  [ -d "$APP/Contents/Resources/$lang.lproj" ] || { missing_langs=1; echo "LANG $lang: FAIL"; }
done
[ "$missing_langs" -eq 0 ] && ok "TEN LANGUAGE LPROJ" || { bad "TEN LANGUAGE LPROJ"; }

has "$APP/Contents/Resources/launch/gvproxy-eim" "LAUNCH RESOURCE gvproxy"
for resource in gvproxy-eim gvproxy-eim-wrapper; do
  [ -x "$APP/Contents/Resources/launch/$resource" ] && ok "$resource executable" || bad "$resource executable"
done
if [ -f "$APP/Contents/Resources/launch/gvproxy-eim" ]; then
  actual=$(/usr/bin/shasum -a 256 "$APP/Contents/Resources/launch/gvproxy-eim" | awk '{print $1}')
  [ "$actual" = "$GVPROXY_SHA256" ] && ok "gvproxy SHA-256" || { bad "gvproxy SHA-256"; echo "  actual: $actual"; }
else
  bad "gvproxy SHA-256"
fi
has "$APP/Contents/Frameworks/Sparkle.framework" "SPARKLE EMBEDDED"

# Info.plist identity.
plist="$APP/Contents/Info.plist"
bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null)
[ "$bid" = "com.lsjop.helldivers2fx.native.phase1" ] && ok "BUNDLE IDENTIFIER" || bad "BUNDLE IDENTIFIER"
ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null)
[ -n "$ver" ] && ok "VERSION ($ver)" || bad "VERSION"
iconfile=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist" 2>/dev/null)
[ "$iconfile" = "AppIcon" ] && ok "INFO.PLIST ICON REFERENCE" || bad "INFO.PLIST ICON REFERENCE"

# Self-contained identity must describe a clean source snapshot and this bundle.
if /usr/bin/python3 - "$APP" <<'PYMETA'
import json,pathlib,plistlib,re,sys
app=pathlib.Path(sys.argv[1])
m=json.loads((app/'Contents/Resources/BuildMetadata.json').read_text())
i=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert re.fullmatch(r'[0-9a-f]{40}',m['commit'])
assert m['version']==i['CFBundleShortVersionString'] and m['build']==i['CFBundleVersion']
assert m['core_version'] and m['built_at']
assert m['configuration']=='Release' and m['source_dirty'] is False
PYMETA
then ok "BUILD METADATA"; else bad "BUILD METADATA"; fi

# Architecture and runtime dependencies.
arch=$(/usr/bin/lipo -archs "$APP/Contents/MacOS/HD2FXNative" 2>/dev/null)
[ "$arch" = "arm64" ] && ok "ARCHITECTURE arm64" || bad "ARCHITECTURE arm64 ($arch)"
if /usr/bin/otool -L "$APP/Contents/MacOS/HD2FXNative" 2>/dev/null | grep -qi python; then bad "PYTHON RUNTIME DEPENDENCY"; else ok "PYTHON RUNTIME DEPENDENCY NONE"; fi

# No Python/Bridge files or references in the bundle.
pycount=$(find "$APP" -type f \( -name '*.py' -o -name '*.pyc' -o -name 'python*' \) 2>/dev/null | wc -l | tr -d ' ')
[ "$pycount" = "0" ] && ok "NO PYTHON FILES" || bad "NO PYTHON FILES ($pycount)"
if find "$APP" -maxdepth 4 -type d -name 'bridge' 2>/dev/null | grep -q .; then bad "NO BRIDGE DIRECTORY"; else ok "NO BRIDGE DIRECTORY"; fi

# Code signature.
/usr/bin/codesign --verify --deep --strict "$APP" >/dev/null 2>&1 && ok "CODE SIGNATURE VERIFY" || bad "CODE SIGNATURE VERIFY"

[ "$fail" -eq 0 ] && echo "RELEASE RESOURCE INTEGRITY: PASS" || echo "RELEASE RESOURCE INTEGRITY: FAIL"
exit "$fail"
