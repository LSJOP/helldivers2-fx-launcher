# HD2FXNative — Full Regression Repair Report

Date: 2026-11-03 · Branch: `feature/full-swift-native-migration` · PR: #3 · Baseline: `01aa179`.

## Root causes repaired

1. **PROTOCOL_ERROR · get_logs** — `AppState.validate` still expected the retired bridge source `bridge_process_session`, while the native core reports `native_core_session`. A single failed validation also aborted the whole `load()` loop, which is why macOS / architecture / native runtime all showed “unknown”. Fixed the validation contract and made `load()` isolate each method so one failure no longer blanks the other panels.
2. **Lost App icon / assets / lproj** — the resource-copy build phase used `rsync --delete`, which erased the compiled `AppIcon.icns` and `Assets.car` and never copied the ten `.lproj` bundles. Replaced with a non-destructive copy of `Resources/` plus `Localization/*.lproj`.
3. **FX launch orchestration** — the game path threw `FX_NOT_RUNNING` instead of auto-starting the verified FX. Now it auto-starts FX once, waits for Guest, waits for Steam login, then sends the game request, with bounded waits and stage events.
4. **Legacy Python Bridge UI text** — ten-language keys (`ui.017`, `ui.035`, `ui.174`, `ui.207`, `ui.240`, `ui.270`, `ui.336`) and the Node-runtime / resource wording (`ui.013`, `ui.178`, `ui.346`) rewritten to native-core wording; `BridgeService.swift` deleted; `BridgeReply`/`BridgeWorkerStatus` renamed to `CoreReply`/`CoreWorkerStatus`; Logs source label changed to “Core”.

## Verification

- Native core checks: **62/62 PASS**. SwiftUI ↔ Native Core integration checks: **20/20 PASS** (including real FX 1.9.8 discovery, fail-closed launch without a selection, honest foreign-FX detection, log-source contract, system-info contract).
- Localization gate: **0 errors**, 454 keys × 10 languages; negative fixtures PASS.
- Debug build: **PASS**. Release build: **PASS**.
- Release resource-integrity gate: **PASS** — icon resource/format, asset catalog, ten lproj, bundled gvproxy SHA-256, Sparkle, bundle id, version, arm64, no Python/Bridge files, code-signature verify.
- Release ad-hoc signature: `codesign --verify --deep --strict` PASS; Gatekeeper `spctl` still REJECTED (no Developer ID/notarization). Sparkle embedded (2.10.1) and unmodified.
- App startup (Release): **PASS** (process alive, no Python subprocess).

## Not verified (require user authorization)

- Real FX launch, Guest authentication, Steam start, game launch, main menu, EAC, multiplayer: **UNVERIFIED**. The FX auto-start orchestration is implemented and unit/integration tested at the code level, but no real FX/SteamOS/game was started.
- Live FX preference apply/restore: **UNVERIFIED** (FX was running; the stopped-FX guard is intentional). Real-domain read succeeded: `cpus=8 memMiB=8192 vulkanDriver="kosmickrisp" metalHUD=false superResolution=false`.
- Finder / Dock / Launchpad icon rendering: **UNVERIFIED** (no GUI observation available); the `AppIcon.icns` and `Assets.car` are present and valid in both Debug and Release bundles.
- Screenshots: still pending recapture after the redesign; manifest records the pending state.

```
HD2FXNative — FULL REGRESSION REPAIR
PROTOCOL_ERROR get_logs: FIXED
ENVIRONMENT PAGE: PASS
FX AUTO DISCOVERY: PASS
FX START ORCHESTRATION: PASS (isolated; real FX launch UNVERIFIED)
UI ↔ NATIVE CORE: PASS
PYTHON RUNTIME DEPENDENCY: NONE
EXTERNAL SCRIPT DEPENDENCY: NONE
LEGACY UI TEXT: REMOVED
APP ICON RESTORED: YES
ORIGINAL ICON VERIFIED: YES (committed appiconset packaged)
DEBUG ICON: PASS
RELEASE ICON: PASS
FINDER ICON: UNVERIFIED
DOCK ICON: UNVERIFIED
LAUNCHPAD ICON: UNVERIFIED
CPU CONFIG: PASS (isolated + real-domain read)
MEMORY CONFIG: PASS (isolated + real-domain read)
VULKAN CONFIG: PASS (isolated + real-domain read)
ONE-CLICK APPLY: PASS (isolated; live write UNVERIFIED)
ONE-CLICK RESTORE: PASS (isolated; live restore UNVERIFIED)
LOCALIZATION: PASS
UPDATE SYSTEM: BLOCKED (no signing/notarization/EdDSA config)
RELEASE RESOURCE INTEGRITY: PASS
AUTOMATED TESTS: PASS
DEBUG BUILD: PASS
RELEASE BUILD: PASS
APP STARTUP: PASS
REAL FX LAUNCH: UNVERIFIED
REAL GAME LAUNCH: UNVERIFIED
MULTIPLAYER: UNVERIFIED
PR #3: UPDATED
LATEST APP: /Volumes/Thunderbolt2TB/HD2-App-Builds/Latest/HD2FXNative.app
OVERALL STATUS: PARTIAL (live launch/multiplayer and distribution remain unverified)
```
