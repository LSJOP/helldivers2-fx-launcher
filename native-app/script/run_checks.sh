#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build evidence
SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"

/usr/bin/python3 -I -B checks/fex_runtime_checks.py >evidence/fex-runtime-checks.txt 2>&1
/usr/bin/python3 -I -B checks/fex_pipeline_checks.py >evidence/fex-pipeline-checks.txt 2>&1
/usr/bin/python3 -I -B script/check_localization.py >evidence/localization-checks.json
/usr/bin/python3 -I -B checks/bundle_name_checks.py >evidence/bundle-name-checks.txt
/usr/bin/python3 -I -B checks/localization_checks.py >evidence/localization-negative-checks.txt 2>&1
/usr/bin/python3 -I -B script/check_readme_screenshots.py >evidence/readme-screenshot-paths.txt 2>&1
/usr/bin/python3 -I -B checks/readme_screenshot_checks.py >evidence/readme-screenshot-checks.txt 2>&1
/usr/bin/python3 -I -B checks/release_history_checks.py >evidence/release-history-checks.txt 2>&1
/usr/bin/python3 -I -B checks/update_resources_checks.py >evidence/update-resources-checks.txt 2>&1

/usr/bin/python3 -I -B checks/proton_release_checks.py >evidence/proton-release-checks.txt 2>&1

# SSH regression: arguments, controlling terminal, password echo, error classes.
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-cache-path "$ROOT_DIR/build/ModuleCache" \
  Models/BridgeModels.swift Core/*.swift checks/SSHChecks.swift \
  -o build/SSHChecks >evidence/ssh-compile.txt 2>&1
./build/SSHChecks >evidence/ssh-checks.txt 2>&1

/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" \
 -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Core/*.swift checks/PrivilegedExecutorChecks.swift \
 -o build/PrivilegedExecutorChecks >evidence/privileged-compile.txt 2>&1
./build/PrivilegedExecutorChecks >evidence/privileged-checks.txt 2>&1
/usr/bin/python3 -I -B script/check_memory_only.py >evidence/memory-only-audit.json

# Runtime network transactions and actual diagnostic protocol validation, isolated.
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" \
 -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Core/*.swift checks/NetworkChecks.swift \
 -o build/NetworkChecks >evidence/network-compile.txt 2>&1
./build/NetworkChecks >evidence/network-checks.txt 2>&1

# Native core contract, isolation and integrity checks.
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-cache-path "$ROOT_DIR/build/ModuleCache" \
  Models/BridgeModels.swift Core/*.swift checks/NativeCoreChecks.swift \
  -o build/NativeCoreChecks >evidence/native-core-compile.txt 2>&1
./build/NativeCoreChecks >evidence/native-core-checks.txt 2>&1

/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-cache-path "$ROOT_DIR/build/ModuleCache" \
  Models/BridgeModels.swift Core/*.swift checks/NativeCoreIntegrationChecks.swift \
  -o build/NativeCoreIntegrationChecks >evidence/native-integration-compile.txt 2>&1
./build/NativeCoreIntegrationChecks >evidence/native-integration-checks.txt 2>&1

/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" \
  -module-cache-path "$ROOT_DIR/build/ModuleCache" \
  Models/BridgeModels.swift Core/*.swift checks/FXIdentityChecks.swift \
  -o build/FXIdentityChecks >evidence/fx-identity-compile.txt 2>&1
./build/FXIdentityChecks >evidence/fx-identity-checks.txt 2>&1

/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Models/LaunchSession.swift checks/LaunchChecks.swift -o build/LaunchChecks >evidence/launch-compile.txt 2>&1
./build/LaunchChecks >evidence/launch-checks.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Services/LocalCredentialStore.swift Services/SessionCredentialManager.swift checks/CredentialChecks.swift -o build/CredentialChecks >evidence/credential-compile.txt 2>&1
./build/CredentialChecks >evidence/credential-swift-checks.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Services/LocalCredentialStore.swift Services/SessionCredentialManager.swift checks/PersistentCredentialChecks.swift -o build/PersistentCredentialChecks >evidence/encrypted-persistence-compile.txt 2>&1
./build/PersistentCredentialChecks >evidence/encrypted-persistence-checks.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Services/GamePerformanceInferenceService.swift checks/PerformanceChecks.swift -o build/PerformanceChecks >evidence/performance-compile.txt 2>&1
./build/PerformanceChecks >evidence/performance-checks.txt 2>&1
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Services/FXSelectionManager.swift checks/FXSelectionChecks.swift -o build/FXSelectionChecks >evidence/fx-selection-compile.txt 2>&1
./build/FXSelectionChecks >evidence/fx-selection-checks.txt 2>&1
/usr/bin/plutil -lint HD2FXNative.xcodeproj/project.pbxproj >evidence/project-lint.txt
cat evidence/native-core-checks.txt evidence/native-integration-checks.txt evidence/fx-identity-checks.txt

/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" -module-cache-path "$ROOT_DIR/build/ModuleCache" Models/BridgeModels.swift Core/*.swift checks/DeploymentChecks.swift -o build/DeploymentChecks >evidence/deployment-compile.txt 2>&1
./build/DeploymentChecks >evidence/deployment-checks.txt 2>&1
cat evidence/deployment-checks.txt
