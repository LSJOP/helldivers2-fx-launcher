#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build evidence
/usr/bin/python3 -I -B checks/bridge_checks.py >evidence/python-checks.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Services/BridgeService.swift Services/TaskManager.swift checks/ServiceChecks.swift -o build/ServiceChecks >evidence/service-compile.txt 2>&1
./build/ServiceChecks "$ROOT_DIR/bridge/bridge.py" >evidence/service-checks.txt 2>&1
/usr/bin/python3 -I -B checks/safety_guard.py >evidence/safety-guard.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift checks/VisualChecks.swift -o build/VisualChecks >evidence/visual-compile.txt 2>&1
/usr/bin/plutil -lint HD2FXNative.xcodeproj/project.pbxproj >evidence/project-lint.txt
cat evidence/python-checks.txt evidence/service-checks.txt
