# HD2FXNative — Full Swift Native Migration Report

Date: 2026-11-03 · Branch: `feature/full-swift-native-migration` (isolated worktree `/Volumes/Thunderbolt2TB/HD2-Native-swift-core-20261103`) · Baseline: `1b26b12` (= `origin/main` at takeover).

## 1. Git takeover state
- main HEAD re-verified as `1b26b129183dc006113becb7f1ef30de8d53c646`; Codex worktree `/Volumes/Thunderbolt2TB/HD2-Native-integration-v2-20261103` was clean and untouched.
- No existing branch/worktree was overwritten. All work happened in a new worktree and new branch.
- `native-app/CoreSnapshot` submodule pinned at `f6dfb4c` and **not modified**; it is no longer packaged or executed.

## 2. Python audit
Audited all 35 Python files in the pinned core plus the bridge (`legacy_operations.py`, `core_adapter.py`, `launch_resources.py`, `performance_configuration.py`, `credential_security.py`) and the launch entry `goal-dxmt-20261026/start-hd2.py`. Feature inventory and file/function mapping: `docs/FUNCTION_MIGRATION.md`.

## 3. Migration matrix
See `docs/FUNCTION_MIGRATION.md`. Every row records Python implementation, Swift implementation, input, output/side effects, safety checks, tests and an honest status (COMPLETE / PARTIAL / BLOCKED / REMOVED).

## 4. Swift Native Core architecture
`native-app/Core/`:
- `CoreSupport.swift` — bounded file/process primitives, SHA-256, redaction, private dirs, advisory locks.
- `SystemProbe.swift` — system/hardware/dependency facts.
- `FXDiscoveryService.swift` + `LaunchResources` — bounded FX discovery, identity/version, bundled gvproxy integrity.
- `ConfigurationService.swift` — revision-guarded launcher settings, backups, restore.
- `PerformanceConfigurationService.swift` — scoped `es.fxgam.steamac` preferences, preview token, receipt, rollback.
- `SSHTransport.swift` — ControlMaster transport; PTY-only password entry.
- `GuestService.swift` — fixed POSIX guest probes and one-shot Steam/game actions.
- `LaunchService.swift` — host identity, FX start, preflight, compatibility, launch orchestration.
- `DiagnosticsService.swift` — bounded redacted history/exports.
- `NativeCoreService.swift` — single actor/dispatch replacing the bridge protocol.

AppState now calls `NativeCoreService`; the UI, six pages, ten languages, Sparkle update module and credentials manager are retained.

## 5. Modified files
Added `Core/*` (10 files), `Resources/launch/*` (gvproxy binary + wrapper + Apache-2.0 license + patch), `Resources/native-locales.json`, `checks/NativeCoreChecks.swift`, this report, migration matrix. Modified AppState, Settings/Environment/Dashboard/DesignSystem views, project file (sources + rsync resource phase), run_checks, localization/doc scripts, READMEs, CHANGELOGs, screenshot manifest. Deleted `bridge/`, `Services/BridgeService.swift`, `script/package_resources.py`, obsolete Python checks.

## 6. Python Bridge removal evidence
- `find build/Release/HD2FXNative.app -name '*.py' -o -name 'python*' -o -name bridge` → empty.
- `otool -L` → no Python libraries. `strings` → 0 matches for `bridge.py`/`legacy_operations`/`python3 -I`.
- No Python process is spawned during startup (verified with `pgrep`).

## 7. External script dependency removal evidence
- Launch resources are inside `Contents/Resources/launch` and hash-verified.
- Real preflight succeeded with no runtime-root parameter: FX `/Applications/FX Steam Launcher.app` 1.9.8, `host_ready: true`, `resource_scope: app_bundle_resources_only`.
- `steam-cdp.mjs` / `check_node.cjs` are replaced natively; dependency row is `not_required`.

## 8. FX version compatibility
Fixtures for 1.9.4 and 1.9.8 pass identity tests; installed 1.9.8 passes real host preflight. Publisher signature requirement verified; unknown/unsigned bundles fail closed. Launch/game compatibility remains UNVERIFIED.

## 9. CPU / memory / Vulkan tests
Range, step, driver, conflict and unrelated-key preservation tests pass against an isolated preference store (20 checks). Commit writes only the five owned keys, verifies the domain, writes a receipt and restores it. **Live FX preference write was NOT executed** because FX was running; the stopped-FX guard (`PERF_RUNNING`) is intentional.

## 10. Game launch verification level
- Pre-launch host checks: **PASS** (real).
- FX process start: **NOT TESTED**.
- Guest SSH authentication: **NOT TESTED** (no credential supplied in this session).
- Steam/Game/main menu/EAC/multiplayer: **UNVERIFIED**. Process existence is never reported as gameplay.

## 11. Automated tests
- Native core: **62 passed, 0 failed** (`evidence/native-core-checks.txt`).
- Launch/GUI state 18, credentials 25, performance inference 15, FX selection 17: PASS.
- Localization negative fixtures: 8 PASS; localization gate: 0 errors (454 keys × 10 languages).
- Documentation/release/update resource checks: PASS.
- Visual OCR checks require a fresh GUI smoke manifest; not run in this change.

## 12. Debug build
`xcodebuild ... Debug` → **BUILD SUCCEEDED**.

## 13. Release build
`xcodebuild ... Release` → **BUILD SUCCEEDED**; ad-hoc re-sign → `codesign --verify --deep --strict` **valid**; independent launch → process alive (APP STARTUP VERIFIED). Gatekeeper `spctl` rejects (not notarized).

## 14. Sparkle signing status
Sparkle 2.10.1 remains embedded and unmodified. No Developer ID identity, notarization credentials or EdDSA publishing configuration exists in this environment → **distribution BLOCKED**; no signature result was fabricated.

## 15. Ten-language check
`zh-CN, en, ja, ko, ru, es, de, fr, pt-BR, zh-TW`: 454 keys each; 12 new native-core keys translated; gate and negative fixtures pass. Translation naturalness still needs human review.

## 16. README updates
Both READMEs now describe the Swift Native Core, remove Python/legacy-directory requirements and mark pre-migration screenshots as pending recapture (manifest updated). CHANGELOGs list migration changes and known issues.

## 17. Git commits and PR
Commit `bf4e7eb` on `feature/full-swift-native-migration` (isolated worktree). Push and PR are **BLOCKED by the environment**: all HTTPS Git operations fail with `LibreSSL SSL_connect: SSL_ERROR_SYSCALL` (direct and via the local proxy), although `gh api` works. No force-push or history rewrite was attempted; the branch remains local.

## 18. Final App path
`/Volumes/Thunderbolt2TB/HD2-App-Builds/Latest/HD2FXNative.app` after validation; historical copies under `Releases/`.

## 19. Known limitations / remaining blockers
- No live Guest authentication, FX start, Steam start, game launch, main menu, EAC or multiplayer verification (authorization required).
- Live FX preference write/restore not executed (FX was running).
- Network profile apply/restore is implemented but not live-tested.
- Ad-hoc signature only; Developer ID + notarization + EdDSA configuration are release blockers.
- Screenshots pending recapture after the UI change.

```
HD2FXNative — FULL SWIFT NATIVE MIGRATION
SWIFT NATIVE CORE: PASS
PYTHON BRIDGE REMOVED: YES
EXTERNAL PYTHON DEPENDENCY: NONE (runtime/app bundle; dev scripts optional)
EXTERNAL SCRIPT DEPENDENCY: NONE
FX AUTO DISCOVERY: PASS
FX MULTI-VERSION SUPPORT: PASS (1.9.4 / 1.9.8 identity; live launch unverified)
CPU CONFIGURATION: PASS (isolated; live write UNVERIFIED)
MEMORY CONFIGURATION: PASS (isolated; live write UNVERIFIED)
VULKAN CONFIGURATION: PASS (isolated; live write UNVERIFIED)
ONE-CLICK APPLY: PASS (isolated; live write UNVERIFIED)
ONE-CLICK RESTORE: PASS (isolated; live restore UNVERIFIED)
RESOURCE INTEGRITY: PASS
LAUNCH PRECHECK: PASS (real host preflight)
REAL GAME LAUNCH: UNVERIFIED
MULTIPLAYER: UNVERIFIED
LOCALIZATION: PASS
UPDATE SYSTEM: BLOCKED (no signing/notarization/EdDSA configuration)
AUTOMATED TESTS: PASS
DEBUG BUILD: PASS
RELEASE BUILD: PASS (ad-hoc signed; not notarized)
APP STARTUP: VERIFIED
GIT STATUS: local commit bf4e7eb; push/PR BLOCKED by network (SSL_ERROR_SYSCALL); main untouched
FINAL APP PATH: /Volumes/Thunderbolt2TB/HD2-App-Builds/Latest/HD2FXNative.app
OVERALL STATUS: PARTIAL (implementation complete; live launch/multiplayer and distribution unverified)
```
