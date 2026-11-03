# FX_INSTANCE_MISMATCH Repair Report

Date: 2026-11-03 · Branch: `feature/full-swift-native-migration` · PR: #3 · Baseline: `2f210ea`.

## Root cause
`LaunchService.parseProcessTable` parsed `ps -ww -axo pid=,ppid=,lstart=,comm=` with Swift `String.split(separator:" ", maxSplits:7, omittingEmptySubsequences:true)`. Unlike the Python bridge's `str.split(None, 7)` (which treats whitespace runs as one separator and strips padding), this left the column-alignment padding before the `comm` field, so the parsed executable path carried leading whitespace (e.g. `"    /Applications/FX Steam Launcher.app/…/steamac-vm"`). The exact-path equality in `checkFXEntry`/`hostIdentity` then compared that padded string against the clean selected path and classified the selected FX's **own** process as `different_fx_copy` → `FX_INSTANCE_MISMATCH`.

A second, latent bug: `hostIdentity` required exactly **one** `steamac-vm` process, but FX legitimately runs **two** (one supervisor + one direct VM child sharing the executable path). Even with the whitespace fix, the pipeline would have stopped at `FX_IDENTITY_UNVERIFIED`.

## Fixes
- `parseProcessTable` now trims the `comm` field (`String(fields[7]).trimmingCharacters(in: .whitespaces)`).
- New `fxSupervisorPID(rows:executable:)` normalizes the 1-or-2-process topology to the supervisor PID (rejects 0, >2, and cyclic topology); `hostIdentity` uses it.
- New `normalizedExecutable`/`normalizedCommand` (symlink resolution + standardization) and `foreignProcesses(rows:executable:)`; `checkFXEntry` compares canonical paths and now reports `selected_fx` and `running_fx` full paths on a genuine mismatch.
- Added `WaitingForFXReady` and `VerifyingFXIdentity` launch stages (with ten-language titles).

## Verification
- **Live read-only check** against the running FX: `steamac-vm` processes = 2 (supervisor pid 55802 / child 55809); parsed commands are clean; `foreign processes = 0`; supervisor = 55802; `check_fx_state` returns `fx_host_running: true`, `fx_version: 1.9.8`, `fx_process_count: 2` — no `FX_INSTANCE_MISMATCH`.
- New FX identity checks: **12/12 PASS** (parser, 1/2/0/>2/cyclic topology, foreign detection, symlink normalization).
- Full suite: native core 62/62, integration 20/20, FX identity 12/12, localization gate 0 errors, documentation checks PASS.
- Debug build PASS; Release build PASS; Release resource-integrity gate PASS; app startup PASS; no Python subprocess.

## Selected vs running FX (observed)
- Selected: `/Applications/FX Steam Launcher.app` — 1.9.8, bundle `es.fxgam.steamac`, exec SHA-256 `683a905a…`.
- Running: `/Applications/FX Steam Launcher.app` (2 processes) — 1.9.8, same bundle/executable. **SAME INSTANCE: YES**.
- The other installed copy `/Applications/FX 绝地潜兵2（脚本专用）.app` is 1.9.4 (different executable hash). If it is running instead, `check_fx_state`/launch still fails closed with `different_fx_copy` and now shows both paths.

## Delivery note
The repaired Release build is verified and staged at `Releases/0.1.0-f219577-Release-identity/HD2FXNative.app` (BUILD-VALIDATION.json present). `Latest` was **not** swapped because the user's app (pid 55717) and the FX it launched (gvproxy inside the current Latest bundle) are actively running; the publish tool correctly refused to replace a running app. Update `Latest` only after the user quits the App and FX normally.

## Not verified (require user authorization)
FX start (auto), Guest connection, Steam start, game launch, multiplayer: UNVERIFIED. No FX/SteamOS/game was modified or terminated.

```
FX INSTANCE IDENTITY REPAIR
ROOT CAUSE: comm column padding not trimmed in process-table parser (plus 2-process topology not normalized)
SELECTED FX: /Applications/FX Steam Launcher.app
RUNNING FX: /Applications/FX Steam Launcher.app (2 processes)
SAME INSTANCE: YES
IDENTITY CHECK: PASS
FALSE POSITIVE FIXED: YES
FX START: UNVERIFIED
GUEST CONNECTION: UNVERIFIED
STEAM START: UNVERIFIED
GAME LAUNCH: UNVERIFIED
MULTIPLAYER: UNVERIFIED
AUTOMATED TESTS: PASS
DEBUG BUILD: PASS
RELEASE BUILD: PASS
PR #3: UPDATED
LATEST APP: staged /Volumes/Thunderbolt2TB/HD2-App-Builds/Releases/0.1.0-f219577-Release-identity/HD2FXNative.app (Latest swap blocked while App/FX running)
OVERALL STATUS: PARTIAL (identity repaired and verified; live launch/multiplayer unverified)
```
