# HD2FXNative full audit — 2026-11-06

Status: **PARTIAL — audit and implementation in progress**. No live operation is counted as passed from isolated tests.

## Scope and source

- Requested baseline: v0.1.0 / 2026110601. Actual latest source retained: `58c4fc1`, build 2026110602.
- Development: `feature/full-native-audit-20261106`, isolated worktree. No main merge or Latest replacement.
- Historical trace recovered at `/Volumes/Thunderbolt2TB/绝地潜兵脚本/HD2-App-Builds/Archives/Worktree-Triage-20261105-031146/untracked/2/STEAMOS_ENVIRONMENT_TRACE_20261104.zh-CN.md`.
- Historical RF FEX and exact Proton-JE are distinct from stock Valve FEX and GE-Proton. A historical name or one file hash is not full integrity proof.

## 1. Root causes and files

- Encrypted credential persistence was deleted from current main; `LocalCredentialStore.swift` and persistence tests remain in Git at `b6544e8` and are being reused without replacing the AES-GCM storage format.
- Password fields exist in setup, generic operation sheets and Settings; separate role fields prompt twice and live boot checks are duplicated across action paths.
- Launch routes through `LegacyOperationSheet`, which contains a second start button and redundant consent.
- Seven navigation cases include a second environment/deployment page. Multiple pages derive status independently from different snapshots.
- Deployment currently discards staging/cache after attempts; safe downloaded-package reuse and resumable transfer require repair. UNKNOWN is already protected from blind overwrite.
- Steam live API mismatch fixes from 2026110602 are retained, including actual app-details callback methods and separate launch/tool reads.

## 2. UI consolidation

PARTIAL: six-page navigation, integrated environment deployment, compact primary actions and details folding pending implementation and GUI review. Existing capabilities must remain accessible.

## 3. Automatic deployment and sources

PARTIAL: exact Proton-JE upstream source, SHA-256/SHA-512 and full 5,609-file / 1,896-link manifest exist. Cache, retry/resume and real missing-component installation acceptance pending. FEX reviewed-download availability must be checked before reporting a safe-source limitation. IPv6 must not change automatically.

## 4. Credential persistence and reuse

PARTIAL: restore the existing installation-local AES-GCM store (0700 directory/0600 files), retain target binding and separate password-challenge verification. No Keychain. One Settings input feeds both roles. Startup restore, incorrect values, update/clear and pending-task resume require actual tests.

## 5. Game launch

PARTIAL: direct single-action launch, cancel/retry and Settings credential recovery pending. No game-menu, EAC or multiplayer success inferred from process presence.

## 6. FX, performance and logs

PARTIAL: verify graceful lifecycle backend before enabling stop/restart. Parameter preview, bounded apply and backup/recovery retained. Saved preferences and live Guest effects must be reported separately. Normalize/redact logging.

## 7. Test VM and GUI results

- Host metadata and open-file audit: `/Applications/FX Steam Launcher测试用.app`, bundle ID `es.fxgam.steamtc`, SSH 2223, actual open writable disk `/Volumes/Thunderbolt2TB/steamos_test.img`. Formal disk is excluded.
- Prior recovery copy exists: `/Volumes/Thunderbolt2TB/FX测试清理备份-20261105-024246`. A current consistent pre-test backup still needs verification/creation after graceful test-VM shutdown.
- macOS accessibility trust: available (`AXIsProcessTrusted() == true`). Real GUI interaction is feasible; no credential contents were read.
- **All live GUI acceptance cases: NOT_TESTED at this checkpoint.** No Guest mutation has been performed in this task.

## 8. Ten-language and documentation checks

PARTIAL: update all ten languages, paired README/changelogs, actual English/Chinese screenshots and provenance after implementation.

## 9. Unresolved items

Implementation and GUI matrix are pending. Unavailable safe FEX artifacts, failed lifecycle support, missing credentials or any GUI acceptance failure must remain explicit PARTIAL/FAIL rather than be described as complete.

## 10. Candidate

Pending build. Separate Candidate only; main and Latest remain unchanged.
