# Python → Swift Native migration matrix

Updated 2026-11-03 · branch `feature/full-swift-native-migration` · baseline `1b26b12`.
Status vocabulary: **COMPLETE** (native implementation + automated checks), **PARTIAL** (native implementation, live path unverified), **BLOCKED** (explicit external constraint). No row claims live gameplay.

| Feature | Python implementation | Swift implementation | Input | Output / side effect | Safety checks | Tests | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FX discovery / identity | `core_adapter.py` `fx_versions`, `validated_fx`, `dependency_discovery.bundle_details` | `FXDiscoveryService.scan/identity/launchTarget` | Application folders, manual path | Candidate metadata only | bundle id `es.fxgam.steamac`, regular non-symlink executable, bounded 2048 scans | NativeCoreChecks FX fixtures, FXSelectionChecks | COMPLETE |
| FX version compatibility | `fx_versions.py`, plist read | `FXDiscoveryService.identity`, `PerformanceConfigurationService.capabilities` | FX bundle | 1.9.4 / 1.9.8 accepted; publisher signature verified | codesign requirement `es.fxgam.steamac` OU `V25VKGTW55`, hash refresh | fixtures, real preflight | COMPLETE (host) |
| Launch resource integrity | `launch_resources.py` | `LaunchResources` + bundled `Resources/launch` | App bundle | SHA-256 verified gvproxy/wrapper | pinned hashes, no symlinks, size caps | hash/missing/tamper tests | COMPLETE |
| steam-cdp.mjs / check_node.cjs | Node + mjs CDP helper | removed; Node no longer required | — | Native launch path does not use Node | dependency row `not_required` | dependency checks | COMPLETE (replacement) |
| CPU / memory / Vulkan config | `performance_configuration.py` (CFPreferences) | `PerformanceConfigurationService` | values + revision + token | Scoped `es.fxgam.steamac` write, backup receipt, rollback | version/rules/ranges, stopped-FX probe, unrelated keys preserved | 20+ in-memory store checks | PARTIAL — live FX write NOT TESTED (FX was running) |
| One-click apply / restore | `performance_apply/restore` | `performance_apply/restore` preview+commit | preview token | atomic-ish write / restore | consent, conflict detection, receipt verification | in-memory apply/restore/rollback | PARTIAL — live write NOT TESTED |
| Launcher settings read/write | `preferences.py` | `ConfigurationService` | JSON patch + revision | backup + atomic replace + lock | revision scope, unknown field/secret rejection, symlink/permission checks | config checks | COMPLETE |
| Configuration backup / restore | `Preferences.save`, ad-hoc backups | `ConfigurationService.snapshot/restore`, performance receipts | manual snapshot | private JSON snapshot, restore keeps pre-copy | envelope SHA-256, path containment, confirmation | backup/restore tests | COMPLETE |
| SSH transport | `preferences.SSHClient` (forkpty) | `SSHTransport` (openpty + ControlMaster) | password/passphrase | multiplexed SSH, CDP forward | secrets never in argv/env/logs, BatchMode commands | compile + code review; live guest NOT re-authenticated | PARTIAL |
| Guest identity / boot binding | `launch_safety.host_identity`, `guest_safety.guard` | `LaunchService.hostIdentity`, `GuestService.connect/verify` | process table, lsof, boot id | read-only identity proof | one FX process, gvproxy child, listener/master/CDP/peer identity, double bind | host identity code path unit-compiled | PARTIAL — no live guest session |
| Guest inspect | `guest_safety.py`, `STATE` | `GuestScripts.state/inspect` (POSIX sh) | SSH | JSON state | read-only, bounded, no user interpolation | parser fixtures | PARTIAL — live parse NOT TESTED |
| FX start | `start-hd2.py` `open` args | `LaunchService.startFX` | selected FX + prefs | launches FX | integrity, resources, target lock, 30 s timeout, no foreign FX | preflight real PASS; start not run | PARTIAL — not launched (user consent) |
| Steam start | `guest_safety` systemd | `GuestScripts.steam` | boot id | one controlled `systemctl --user start steam.service` | idle/managed-service/boot guards, never retries | code path compiled | PARTIAL — live NOT TESTED |
| Game launch | `start-hd2.py` `_main` | `LaunchService`/`NativeCoreService.launchGame` | consent | `steam -applaunch 553850`, waits for process | compat tool/FEX/ntdll/wine hashes, proxy, duplicate-launch checks | preflight only | PARTIAL — REAL GAME LAUNCH UNVERIFIED |
| Launch preflight | `preflight_launch` | `LaunchService.preflight` | selected FX | host readiness + explicit guest unverified | integrity, resources, SSH, local host | real `/Applications` FX 1.9.8 PASS | COMPLETE (host only) |
| Observe launch | `observe_launch` | `runGUI observe_launch` | SSH | process counts only | no menu/EAC/multiplayer inference | compiled | PARTIAL |
| EAC / multiplayer | probes in `start-hd2.py` | not inferred; reported `unverified`/`not_requested` | — | — | never fabricates | none | BLOCKED — outside authorization |
| Logs / diagnostics | `network_diagnostics.py`, bridge ring | `DiagnosticsStore`, native events, exports | actions | bounded redacted JSONL/report | redaction, 8 MB limit, no credentials | export/history checks | COMPLETE |
| Network profile | `network_profile.py` | `NetworkProfileService` | consent | reversible Wi-Fi off/on profile | wired-default guard, verify, rollback | code only | PARTIAL — live network NOT TESTED |
| Update system | `update_checker.py` | existing Sparkle 2 + `UpdateReleaseService` (unchanged) | channel | appcast/HTTPS | require verified service; unconfigured state | release-history checks | BLOCKED — no Developer ID/EdDSA public config for distribution |
| Ten-language UI | `launcher-20261026/locales` | `Resources/native-locales.json` (454 keys × 10) | language | native strings | localization gate, no English fallback | gate + negative fixtures | COMPLETE |
| Python bridge | `bridge/*.py`, `legacy_operations.py` | deleted; `NativeCoreService` | — | none | bundle scan | source/bundle scans | REMOVED |
| Original script directory | `CoreSnapshot` packaging + runtime root | no runtime root required | — | none | bundle resources only | real preflight | REMOVED (submodule retained as history) |

Known constraints: no live Guest authentication, FX start, Steam start, game launch or multiplayer verification was performed (user authorization required). FX preference writes require stopping FX. Distribution needs Developer ID signing and notarization.

## Unified candidate audit - 2026-11-04

This section supersedes older credential/live-acceptance wording above. Source-level implementation and isolated tests are distinct from live configuration or gameplay acceptance.

| Capability | Actual Native implementation | Python/reference comparison | Current boundary |
| --- | --- | --- | --- |
| FX discovery / selection / version | FXDiscoveryService + FXSelectionManager, bounded scans and canonical identities | dependency_discovery / fx_versions | Implemented; host checks and fixtures, not Guest readiness |
| CPU / memory / Vulkan / Metal HUD | PerformanceConfigurationService: 1.9.4/1.9.8, ranges/driver evidence, stopped-FX guard, scoped preview/backup/apply/restore | performance_configuration.py | PARTIAL product flow; no real FX preference write this task; no unsupported hardware tuning claim |
| FX backup / restore | Revision/token receipts and unrelated-key preservation | CFPreferences scope | Implemented; isolated store tests; running FX blocks writes |
| Credentials | SessionCredentialManager, independent SSH/sudo memory states and target scope | Replaces historical keychain_store/preferences persistence | Memory-only; no old credential read/delete; real candidate authentication NOT TESTED |
| Independent sudo | GuestPrivilegedExecutor: stdin-only per-call auth, no cache dependency, closed operations | Original forkpty/SSH helpers; fixes migrated two-call cache assumption | Synthetic multi-call checks; real new executor acceptance NOT TESTED |
| Guest identity | Host supervisor/network/listener/SSH peer plus Guest boot/marker | launch_safety / guest_safety | Preserved and extended to pre-send credential binding |
| Guest IPv6 | Environment-only full-interface snapshot, four runtime controls, exact confirmation, receipt, verification and recovery; never a launch prerequisite | Original ensure_ipv4 behavior | PARTIAL; no real writes authorized/performed; no persistent sysctl-file edits |
| Guest proxy | Read-only environment/drop-in inspection; game launch option is checked, not auto-written | Legacy per-game proxy vs Steam drop-in distinction | PARTIAL; automatic proxy repair/rollback not implemented |
| Compatibility files | Pinned FEX, NTDLL, Wine DLLs and Proton tool checks | Verified historical launch constants | Read-only validation, not install/repair; no anti-cheat changes |
| Steam installation/login | GuestScripts inspect service/process and bounded login log evidence | Original state() checks process before Logged On | PARTIAL; readiness now requires service + process + login evidence; log alone is insufficient |
| Game install / launch options | Steam library hashes/launch-option read-only checks; missing prerequisites fail closed | Original BASE_LAUNCH/PROXY_LAUNCH | PARTIAL; no one-click install or SetAppLaunchOptions equivalent implemented |
| DX11 | Not injected by current Native launcher | Historical diagnostics mention --use-d3d11; current original BASE_LAUNCH/PROXY_LAUNCH has no DX11 suffix | No new DX11 option added; do not infer renderer compatibility |
| Game launch | Guarded Steam service start then steam -applaunch 553850, bounded process wait | Original Steam startup and launch request | Implemented path, live menu/playability/EAC/multiplayer NOT TESTED |
| Update system | Sparkle + signed-feed/service trust gates retained; Security APIs validate code | Original updater distinct from FX/Guest | No signing credentials modified; no public release configured by this task |
| Theme, icon, ten languages | Shared SwiftUI/AppKit UI; UI bar removal integrated; new session credential panel | Existing HELLDIVERS assets retained | Candidate build gates; refreshed credential screenshots pending if capture unavailable |

Overall automated “download FX -> install Guest/game -> configure everything -> play” workflow is PARTIAL. Native buttons and read-only snapshots do not establish that missing install/configuration backends exist. No runtime Python Bridge or original-script dependency is restored.

Network migration details: [full parity audit](PYTHON_TO_SWIFT_FEATURE_PARITY_AUDIT.md) and [network guide](STEAMOS_NETWORK_SETTINGS.md).
