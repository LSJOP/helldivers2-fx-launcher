#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build evidence
/usr/bin/python3 -I -B checks/performance_configuration_checks.py >evidence/performance-configuration-checks.txt 2>&1
/usr/bin/python3 -I -B checks/bridge_checks.py >evidence/python-checks.txt 2>&1
/usr/bin/python3 -I -B checks/migration_checks.py >evidence/migration-checks.txt 2>&1
/usr/bin/python3 -I -B checks/credential_checks.py >evidence/credential-python-checks.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Services/SessionCredentialManager.swift Services/BridgeService.swift Services/TaskManager.swift checks/ServiceChecks.swift -o build/ServiceChecks >evidence/service-compile.txt 2>&1
./build/ServiceChecks "$ROOT_DIR/bridge/bridge.py" >evidence/service-checks.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Models/LaunchSession.swift checks/LaunchChecks.swift -o build/LaunchChecks >evidence/launch-compile.txt 2>&1
./build/LaunchChecks >evidence/launch-checks.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Services/SessionCredentialManager.swift checks/CredentialChecks.swift -o build/CredentialChecks >evidence/credential-compile.txt 2>&1
./build/CredentialChecks >evidence/credential-swift-checks.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Services/GamePerformanceInferenceService.swift checks/PerformanceChecks.swift -o build/PerformanceChecks >evidence/performance-compile.txt 2>&1
./build/PerformanceChecks >evidence/performance-checks.txt 2>&1
/usr/bin/python3 -I -B checks/safety_guard.py >evidence/safety-guard.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift checks/VisualChecks.swift -o build/VisualChecks >evidence/visual-compile.txt 2>&1
/usr/bin/plutil -lint HD2FXNative.xcodeproj/project.pbxproj >evidence/project-lint.txt
cat evidence/python-checks.txt evidence/service-checks.txt
