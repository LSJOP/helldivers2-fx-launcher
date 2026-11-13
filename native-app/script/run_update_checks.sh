#!/usr/bin/env bash
set -euo pipefail
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_ROOT"
mkdir -p build evidence
FRAMEWORK_ROOT="$APP_ROOT/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
[[ -d "$FRAMEWORK_ROOT/Sparkle.framework" ]] || { echo 'Build once to resolve pinned Sparkle first' >&2; exit 1; }
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path build/ModuleCache \
    UpdateHelper/ArchivePathPolicy.swift UpdateHelper/UpdateZIPPreflight.swift Services/UpdateReleaseService.swift checks/UpdateChecks.swift -o build/UpdateChecks >evidence/update-service-compile.txt 2>&1
./build/UpdateChecks >evidence/update-service-checks.txt 2>&1
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path build/ModuleCache \
    -F "$FRAMEWORK_ROOT" -framework Sparkle -Xlinker -rpath -Xlinker "$FRAMEWORK_ROOT" \
    Models/BridgeModels.swift Core/*.swift \
    UpdateHelper/ArchivePathPolicy.swift UpdateHelper/UpdateZIPPreflight.swift Services/UpdateReleaseService.swift Services/AppUpdateManager.swift checks/UpdateManagerChecks.swift \
    -o build/UpdateManagerChecks >evidence/update-manager-compile.txt 2>&1
./build/UpdateManagerChecks >evidence/update-manager-checks.txt 2>&1
/usr/bin/python3 -I -B checks/update_resources_checks.py >evidence/update-resources-checks.txt 2>&1
/usr/bin/python3 -I -B checks/release_history_checks.py >evidence/release-history-checks.txt 2>&1
cat evidence/update-service-checks.txt evidence/update-manager-checks.txt evidence/update-resources-checks.txt evidence/release-history-checks.txt

/usr/bin/python3 -I -B checks/update_zip_checks.py
