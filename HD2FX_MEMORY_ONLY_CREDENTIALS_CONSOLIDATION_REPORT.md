# HD2FXNative memory-only credentials consolidation report

Date: 2026-11-04 (Asia/Shanghai). Candidate only; no Latest publication, main merge, Guest mutation, old credential read/migration/deletion or formal release.

## Git and preservation — PASS

Original 14 local branches / 5 worktrees; integration adds one branch/worktree (15 / 6). Full HEAD, dirty/untracked files, unique/unpushed commit inventory: [branch inventory](docs/NATIVE_BRANCH_INVENTORY_20261104.md). All original local heads have recoverable refs under `refs/codex-backups/memory-only-20261104/`. No stash existed. No branches/worktrees deleted: active/unknown ownership, original unknown files and archive history are preserved. Cleanup is PARTIAL by design.

PR #3 development target is `feature/full-swift-native-migration`. Implementation worktree: `/Volumes/Thunderbolt2TB/HD2-Native-memory-only-20261104`, branch `integration/memory-only-20261104`; isolated because original primary worktree contains an unknown untracked environment trace. Baseline `7725cacad5498a3f92fcdbfb649d324bff5f86fb` retains `1188d59`. UI branch `918db0a` merged with two changelog conflicts resolved by retaining both features; merge `e577aa665aa72fe0c1c774f6fb6b5563e7042a1d`. Main remains `1b26b129183dc006113becb7f1ef30de8d53c646`. No forced update permitted.

## Root cause and credential design — PASS (isolated)

Two distinct historical faults: OpenSSH concatenates remote argv, losing an unquoted empty sudo prompt (fixed in 1188d59); later independent SSH channels used noninteractive sudo relying on a timestamp from another invocation. A successful password test does not authorize another channel. AUTH_REQUIRED alone does not prove an incorrect password.

SessionCredentialManager now owns independent SSH password/key passphrase and sudo password solely in process memory. Four states: NOT_PROVIDED, PROVIDED, VERIFIED, FAILED; input changes invalidate verification, actual challenge success establishes verification, rejection allows fresh entry. Clear/exit releases references; Swift String physical erasure is not guaranteed. No defaults, files, vault, system credential calls, migration or cleanup. Legacy `remember_password` config bool is accepted but inert.

Target binding includes canonical FX path/executable hash/config revision/FX PID+start identity, verified listener ownership, full SSH peer/Guest identity and Guest boot when available. Change/loss rejects reuse and clears prior credentials. SSH masters have random per-process namespaces and only owned masters close on clear/exit. New App processes cannot inherit prior App master authentication.

GuestPrivilegedExecutor owns every active privileged path: fixed root UID verification or validated IPv6 values on the exact boot. Each invocation uses `-k` (ignores timestamp); supplied password uses `-S` and a fixed challenge, exclusively through stdin. Remote script is safely quoted, target stdin is `/dev/null`; no password in argv, environment, script, temp file or diagnostics. Passwordless policy success does not verify an entered password. No sudoers/NOPASSWD/host-key weakening. Unused legacy privileged paths removed; historical empty-prompt regression remains tested.

Errors distinguish missing input, rejection, sudo policy denial, SSH transport/authentication, identity change, timeout/cancel and command failure. Nested logs/diagnostics redact secrets. Static audit scans all 37 production Swift files; code-signing Security APIs remain intact. Crash-report memory guarantees are NOT TESTED; no secret is intentionally attached to diagnostics.

Changed production modules: SessionCredentialManager, AppState, SettingsView, BridgeModels, SSHTransport, LaunchService, NativeCoreService, GuestService, ConfigurationService, SmokeRunner, localization catalogs/bundle strings, version/build settings. Removed credential vault and SecItem credential APIs; no old item queried/deleted. Build-time notarization keychain-profile tooling is unrelated and preserved. See [architecture](docs/MEMORY_ONLY_CREDENTIAL_ARCHITECTURE.md).

## sudo and safety verification

| Item | Status | Evidence / limit |
|---|---|---|
| Credential lifecycle/reuse/clear/target changes/new instance | PASS | 25 isolated credential checks |
| SSH argv/PTY/no echo/errors/process master isolation | PASS | 28 SSH checks, synthetic credentials |
| Privileged command boundary | PASS | 30 isolated executor checks using production argument/script builder and CoreProcess runner |
| Three separate calls without timestamp reliance | PASS | Fixture sudo requires fresh stdin and -k each time; target UID 0 each call |
| Wrong/missing password, policy denial, SSH 255, bad result | PASS | Distinct structured errors in fixture coverage |
| Quoting/stdin EOF/argv secret absence | PASS | Target receives EOF; shell quote roundtrip |
| Timeout/cancel/identity loss/approval gate | PASS | Closed operation and target checks |
| Real Guest SSH / sudo / multiple calls | NOT TESTED | Earlier user terminal/App proof is historical and not this candidate executor |
| Real IPv6 apply/recovery/manual restore | NOT TESTED | No live mutation authorized or executed |
| Keychain prompt | NOT OBSERVED | Isolated App screenshot launch only; no real authentication interaction |

Tests do not execute a privileged remote operation against a real Guest. Production executor defaults to /usr/bin/ssh; fixture tests inject only the process boundary and use synthetic sudo/id executables. This is not live SSH/sudo acceptance. None of the twenty requested scenarios is represented as real Guest PASS solely from fixtures.

## Functional audit and known issues

Full implementation/original Python comparison: [function matrix](docs/FUNCTION_MIGRATION.md).

| Capability | Implementation | Live acceptance |
|---|---|---|
| FX discovery/selection/version/identity | Implemented; strict topology and publisher checks retained | PASS read-only local discovery, not launch |
| CPU/memory/Vulkan/Metal HUD backup/apply/restore | Scoped supported-version backend exists | NOT TESTED live writes; overall PARTIAL |
| Guest SSH/identity/sudo | Production paths + memory-only binding | NOT TESTED on candidate Guest |
| IPv6 exact preview/consent/backup/verify/recovery/restore | Implemented for four known switches | NOT TESTED live; CheckingCompatibility NOT TESTED |
| Guest proxy and compatibility assets | Existing bounded paths/hash checks retained | NOT TESTED live; configuration PARTIAL |
| Steam readiness | Requires live process + service + login evidence | NOT TESTED |
| Game launch options | Reads/requires existing four tokens; no complete automatic writer | PARTIAL; actual options NOT TESTED |
| DX11 | No new DX11 flag injected; original Python default does not add it | NOT TESTED actual game compatibility |
| Game launch/process/main menu/multiplayer | Existing launch chain retained; stages separate | All NOT TESTED |
| Sparkle/icon/native arm64/resources | Bundle gate | Local artifact verification only |

Environment drift during regression: `/Applications/FX Steam Launcher.app` is now 1.9.9. The original integration test hardcoded 1.9.8 and failed two assertions; corrected to compare actual installed Info.plist with Core discovery/state. This proves reporting consistency, not 1.9.9 performance/configuration/game support. No installed FX modified.

Guest IPv6 writes now preview exact all/default/eth0/lo old/target values, reason and Guest/FX binding; require explicit matching approval, private pre-write receipt, in-command boot check and post-write verification. Bounded recovery only follows command-start evidence; ambiguous outcomes retain restore_required. Manual restore requires unchanged boot/FX/current values and reverse preview. Reboot may invalidate restoration of these runtime-only switches. No live CheckingCompatibility PASS claim.

## Tests and build

Final full run_checks.sh completed PASS: SSH 28, privileged executor 30, Core 62, integration 22, FX identity 16, launch 18, credentials 25, performance 15, FX selection 17; locale negative 8, screenshot negative 8, release-history 10 and updater-resource 5. Documentation 15/15 and 16 bilingual screenshot references PASS. Candidate path/build time/commit/executable hash/signatures and bundle gate are appended after freezing the implementation. Debug builds already passed during implementation; final Release is not claimed until completed. Ten languages retain equivalent keys and placeholders; real English/Chinese screenshots are captured from an isolated dirty working snapshot, with that provenance rather than a clean-release claim. Interactive SecureField clicks and every-language visual quality remain NOT TESTED.

## Release readiness — NOT READY

Candidate delivery is authorized; formal publication is not. Remaining live Guest auth/compatibility/game/multiplayer acceptance and incomplete automatic game-option/configuration flows prevent READY. Latest and historical Releases/rollback copies remain untouched. Next user step after delivery: open the candidate, re-enter independent SSH/sudo credentials, perform read-only connection/root checks; review any exact Guest mutation preview before separately authorizing it. Game process detection does not establish playability.
