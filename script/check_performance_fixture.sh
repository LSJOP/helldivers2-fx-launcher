#!/usr/bin/env bash
# Same sources and flags as run_checks.sh; only for changes to this fixture.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../native-app" && pwd)"
cd "$ROOT_DIR"
mkdir -p build
SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Services/GamePerformanceInferenceService.swift checks/PerformanceChecks.swift -o build/PerformanceChecks
./build/PerformanceChecks
