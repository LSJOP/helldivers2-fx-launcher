# Python → Swift feature parity audit

2026-11-04. Source: `/Volumes/Thunderbolt2TB/绝地潜兵脚本/HD2-StonkGuy-Fork-20261024`. Swift paths below are under `native-app`. This is source and isolated-test parity, not gameplay acceptance. COMPLETE means a production implementation exists with the indicated scope; live evidence is separate. No Python Bridge is restored.

| Original feature | Python implementation | Swift implementation | Migration | Real availability | Test scope |
| --- | --- | --- | --- | --- | --- |
| FX discovery | `runtime_dependencies.py`, helper APP selection | `Core/FXDiscoveryService.swift` | Complete, bounded discovery | Host metadata; discovery is not running-instance proof | FX selection + NativeCore fixtures |
| FX instance selection | `menu.py/edit_ssh`, helper bound APP | `Services/FXSelectionManager.swift`, AppState | Complete, explicit target | Saved target revalidated | Selection fixtures |
| FX start | `goal-dxmt-20261026/start-hd2.py/main` | `Core/LaunchService.swift/startFX` | Complete within dedicated environment | No real start performed this task | Identity/start fixtures |
| FX version | `collect_status`, dependency inspection | FXDiscoveryService / preflight | Complete | Host file metadata only | NativeCore fixtures |
| Guest OS detection | helper STATE, `guest_safety.py` | GuestService / inspectGuestEnvironment | Complete | Identity-bound SSH needed | Guest parser/identity fixtures |
| SSH | `launcher-20261026/ssh_settings.py` and helper session | SSHTransport / testSSH | Complete | Current-process authenticated master | SSH regression; no password collected in this task |
| sudo | legacy session privilege path | GuestPrivilegedExecutor / testSudo | Complete in code | Each call independently authenticates; UI acceptance not inferred | Production executor with synthetic sudo/transport |
| Credentials | saved-password/Keychain paths in ssh_settings/menu | SessionCredentialManager | Intentionally replaced, not literal parity | Process memory only; roles separate | Credential + no-store static checks |
| Guest identity | `launch_safety.py`, `guest_safety.py` | LaunchService hostIdentity / GuestService.verify | Complete | FX ancestry, endpoint, peer, boot and marker retained | Identity regression |
| IPv6 | helper ensure_ipv4; guest_safety apply/restore | SteamOSNetworkService / GuestPrivilegedExecutor.networkIPv6 | Complete in code; changed interaction | Environment-only preview/confirmation, enable/disable/restore; runtime only | Network transaction fixtures; real writes NOT TESTED |
| Proxy | configure_steam_proxy; network modes | NetworkProfileService + Guest read probes | Partial | Host profile exists; no new automatic Guest proxy mutation | Host-profile isolated tests; live changes NOT TESTED |
| VM footer | `status_monitor.py/snapshot`, GUEST_STATUS | NetworkDiagnosticsService + identity-bound SSH | Complete, explicit action replaces footer polling | SSH request RTT, not ICMP or general Internet health | Fixture pass/disconnect/timeout |
| Steam TLS footer | status_monitor.steam_latency | NetworkDiagnosticsService.curlArgs + Host curl | Complete with documented transport difference | Verified HTTPS through local 7890 proxy; curl HEAD adds HTTP roundtrip | TLS exit/status fixtures; live evidence in migration report |
| PlayFab | helper PLAYFAB_PROBE, monitor_playfab | Guest curl via NetworkDiagnosticsService | Complete in code | Guest direct and gateway-proxy TLS; no login or multiplayer inference | Controlled certificate failure/pass/timeout |
| UDP/STUN | helper UDP_MONITOR, monitor_udp; footer latest_launch_probe | Guest bash UDP + Swift STUN parser | Complete in code with capability checks | Same two targets ×2, counters/socket counts; unsupported tools explicit | Transaction/type/cookie/length fixtures; live evidence separate |
| Old diagnostics dashboard | network_diagnostics.py collect/report | DiagnosticsService / DiagnosticsStore | Partial | Host metadata/history exports; prior footer history not silently imported | NativeCore integration |
| Compatibility hashes | helper STATE | LaunchService.compatibility | Complete for pinned historical toolchain | Hashes are prerequisites, not proof of EAC/game health | Fingerprint mismatch regression |
| Game launch options | helper configure_launch_options / steam-cdp.mjs | LaunchService.launchOptionsReady | Partial | Read/check retained; generic edit of user launch options not migrated | Contract checks; no game-file writes |
| Steam start | helper steam service prepare | GuestService.steam / NativeCoreService | Complete within existing policy | Current service required, process alone insufficient | State machine fixtures |
| Game launch | helper steam -applaunch | NativeCoreService.launchGame / GuestScripts.launchGame | Complete code path, live unverified | IPv6 removed; other compatibility/identity gates retained | Launch fixtures and source call-chain regression |
| Game observation | status_monitor / helper game PID + EAC monitoring | LaunchSession / observeLaunch / GuestService | Partial | Process and EAC evidence separate from menu, single player, multiplayer | Launch/EAC fixture checks |
| PlayFab/UDP post-launch hook | run_post_launch_checks | Explicit Environment diagnostics | Intentionally decoupled | No network probe or diagnostic result blocks launch | Launch-chain regression |
| Logs/export/history | network_records.py / network_diagnostics.py | CoreRedaction / DiagnosticsStore / Logs | Partial | Bounded redacted exports; no raw account/peer values | Export/privacy fixtures |
| Configuration backup | settings/backup helpers | ConfigurationService / CoreFS | Complete for owned settings | Revision/atomic write; not whole-VM backup | Integration fixtures |
| Configuration restore | restore helpers / guest_safety | ConfigurationService / SteamOSNetworkService | Partial | New trusted same-boot IPv6 receipts only; old experiment restore scripts never executed | Drift/untrusted snapshot/rollback fixtures |
| CPU performance | performance_manager.py / defaults / taskset | PerformanceConfigurationService / inference | Partial | Scoped Host preferences; no automatic game affinity write | Performance fixtures; live changes NOT TESTED |
| Memory performance | performance presets | PerformanceConfigurationService | Partial | Source-backed bounds, no invented universal preset | Performance checks |
| Vulkan | FX CLI and settings / STATE | LaunchService / PerformanceConfigurationService | Partial | Actual selection/metadata checks; no GPU render acceptance | Hash/config fixtures |
| Updates | manage_update.py / update_installer.py | AppUpdateManager / Sparkle services | Partial, different architecture | Signed Native updates; not FX/Guest updater; configured feed needed | Update/history tests; distribution NOT TESTED |
| Ten languages | locales/*.json, i18n.py | NativeStrings / native-locales.json / lproj | Complete resource coverage | Translation naturalness remains manual review | Ten-language gate + negative fixtures |
| Terminal layouts/emblems | menu.py / ui2.py | Existing SwiftUI tactical navigation | Intentionally replaced | Terminal-only customization is not a missing Native backend | UI smoke scope |
| Match history/manual outcome | network_records.py | DiagnosticsStore record_match/history | Partial | User outcome is not independently verified multiplayer | History fixture checks |
| Setup/dependency installation | dependency_discovery / setup wizard | DependencyProbe + read-only guidance | Partial | No automatic FEX/JE installer for a fresh VM | Metadata checks only |
| External performance/repair experiments | goal-rf, goal-dxmt, startup-repair, HUD tools | No automatic equivalent | Not migrated intentionally | Dangerous/experimental recovery must not run from normal UI | NOT TESTED |

No original network endpoint was declared obsolete without evidence. Guest Python execution is replaced with fixed shell utilities orchestrated and parsed by Swift. Missing curl/bash/timeout/base64/dd reports UNSUPPORTED; certificate rejection is FAIL and timeout remains inconclusive. The UDP implementation validates response length more strictly than the original, per RFC 8489.

Remaining priorities: P1 live identity-bound Guest probe acceptance and independently authenticated sudo acceptance; P1 fresh-VM compatibility/setup research; P2 safe launch-option editing and historical diagnostic import. Do not expand this task into dependency installation, proxy management, game settings or update publication.
