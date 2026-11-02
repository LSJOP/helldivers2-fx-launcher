# Function migration — HD2_NATIVE_APP_FUNCTION_MIGRATION_v1.0.0

Baseline: pinned `legacy-script` commit f6dfb4c (original launcher 0205aca; separate Native metadata snapshot). Archive content is not modified. Status describes actual Native/backend wiring and evidence, not game compatibility.

| Legacy capability / source | Native scope | Status |
| --- | --- | --- |
| Entry/menu `Start.command`, `menu.py:menu` | Five SwiftUI pages; preserve native navigation | 已迁移 |
| Host/FX metadata `dependencies.py`, `dependency_discovery.py` | Real bounded metadata and full discovered paths; process/runtime claims require the separate explicit inspection | 已迁移 |
| Launch/runtime dependency guards `dependencies.inspect_runtime` | Explicit detailed inspection, configured legacy root; no auto Node execution on refresh | 需要进一步验证 |
| Game launch `start-hd2.py:main`, `launch_safety.Session` | Native preflight, streamed stages, errors, duplicate protection and guarded original launch. Live FX/Guest reached; gameplay acceptance remains pending | 部分迁移 |
| Performance profiles `performance_profile.py`, `performance_catalog.py` | Read/browse and explicit original apply | 需要进一步验证 |
| Configuration `preferences.py` | Real editor/read/save, original validation plus unknown-field preservation, revision checks, private backup and atomic replace; isolated write/failure checks passed | 已迁移 |
| SSH/Keychain `preferences.py`, `keychain_store.py` | Explicit SSH test, secret through stdin, original optional Keychain behavior; no live authentication performed | 需要进一步验证 |
| Guest/Steam `start-hd2.state`, `network_records.guest_snapshot` | Explicit connected inspection; never implied by host metadata | 需要进一步验证 |
| EAC `capture_eac_baseline`, `check_eac`, `guest_safety.py` | Original fresh launch baseline and separate progress stage; not a static health assertion | 需要进一步验证 |
| Network `network_profile.py`, `network_diagnostics.py` | Explicit inspection/test, reversible profile, original prerequisites | 需要进一步验证 |
| Match history/export `network_diagnostics.Store` | Real user-submitted outcomes, bounded history and export in Application Support; isolated record/redaction checks passed | 已迁移 |
| Logs/errors `say`, `PROGRESS_HOOK`, Bridge service | Real streamed stages/errors, search/filter/copy, bounded/redacted logs; cancellation and foreign-progress rejection checked | 已迁移 |
| Successful network snapshot `network_records.capture/save` | Explicit original collection/save, potentially SSH | 需要进一步验证 |
| Environment/report `menu.collect_status/export_report` | Structured local/runtime report; bounded response/export | 部分迁移 |
| Update check/channel/notes `update_checker.check` | Original query retained in Core; Native settings/menu now use separate Sparkle 2 manager. Real signed feed/release not configured; no update installation acceptance | 部分迁移 |
| Automatic update install | Original `INSTALL_ENABLED=False` | 不适用 |
| FX version switching | Original archived menu has no selection/switch implementation; metadata snapshot is not proof of such a legacy UI capability | 不适用 |
| Ten locales `i18n.LANGUAGES`, `locales/*.json` | zh-CN, en, ja, ko, ru, es, de, fr, pt-BR, zh-TW; preserve catalogs; Native-only text coverage tracked separately | 部分迁移 |
| Help/changelog/folder `help_center.py`, `menu.instructions` | Native help/catalog/report entrypoints; archive remains accessible | 部分迁移 |
| Terminal ASCII emblem/layout/intro/TTY | Archive-only presentation; Native tactical theme replaces TTY behavior | 不适用 |

Live FX/Guest/SSH/Steam/EAC/multiplayer success remains unverified until an explicit user operation produces fresh evidence. Fixture checks must not be described as a live-game launch. Unknown configuration fields must be preserved; legacy `preferences.save` alone discards them, so Native uses validated merge plus optimistic conflict checking and backup. Large runtime assets are not installed or moved. No archive source is rewritten.

Current focused evidence: Xcode Debug build passed; 18 protocol/metadata checks, 14 isolated migration checks and 21 service checks passed. One bundled-App smoke passed catalog discovery (20 operations), all ten original locale resources, real read-only configuration access and launch rejection without consent/runtime root. Static audit guard confirms automatic metadata operations cannot write, execute processes, connect networks or access SSH/Keychain/settings. No real launch, SSH, system network change, performance write or multiplayer acceptance was performed. New Native translations remain partial, with explicit English fallback.

## Phase 2 — launch evidence (2026-11-02)

- Local records located and read: `绝地潜兵2成功启动经验_20261026.md` and `三小时联机成功环境记录_20261028.md`, in the existing private self-use launcher directory. Raw records, configuration and logs are not copied into this repository.
- Historical facts: dedicated FX 1.9.4 on M4 Pro/macOS 27.2, patched FEX (eac-main plus PR 6/7 and local PR 20 RF candidate), Proton-JE `11.0-20261014-3`, D3D12/Vulkan/KosmicKrisp, `FEX_DISKCACHE=0` and `FEX_NEEDSSECCOMP=1`. The October 26 record reports visible ship/menu interaction and a repeated cold launch; it explicitly did not establish ground-task acceptance. October 28 multiplayer feedback is historical and outside this phase.
- Preserved configuration: 8 vCPU / 8192 MiB, 6144 MiB GPU budget, HUD/MetalFX off; the later recorded launch retains the Host HTTPS proxy even with TUN. This is evidence of one combination, not proof that any single setting fixes ordinary FX or other systems. No runtime, disk, Steam, game or EAC file is replaced.
- Fresh read-only checks: actual FX/gvproxy hashes and root-dependent JS/wrapper match the pinned records/archive. Native launch preflight passes. The Native App started FX and authenticated Guest/SSH; a subsequent identity-bound read observed one Steam process and no game process.
- Real FX uses a supervisor and one direct VM child with the same executable. The Native adapter accepts only this proven lineage (or the original single-process case), retains raw child PID/start evidence, and reuses every original listener, SSH peer, CDP, hash and Guest-boot check. Ambiguous roots, multiple children and changed identities still fail closed.
- Launch currently stops at a concrete Guest runtime IPv6 change preview. Approval and backup/recovery are required before writing; all other configuration changes remain separately gated. Main menu and single-player are **unverified** until actual game evidence or explicit user confirmation. Multiplayer probes are not requested; original fresh EAC handling is retained.
- Code checks: Debug build passed; 18 protocol/metadata, 23 isolated migration, 22 service and 7 launch-state checks cover the affected boundaries. Process detection never populates gameplay confirmations; final process exit rejects late success frames. These fixtures do not prove real gameplay.

Compatibility fix (`HD2_NATIVE_APP_FX_COMPATIBILITY_FIX_v1.0.0`): the old Chinese error is raised by pinned `start-hd2.py:_main` when `state()['verified_network']` is false. That field is added on the host by `network_ready()` (expected gvproxy files/hash and running command), not returned as a Guest EAC result. A reachable SSH port previously allowed Core to reuse an already running different FX before this check. Native now rejects foreign FX before connection, checks the selected host process and expected transport before emitting FX-done, and preserves a negative legacy readiness result instead of overriding it with a later probe. The original wrapper/arguments, hash/identity guards and Guest compatibility checks remain unchanged. No separate ordinary-FX single-player entry was found. After the other FX was normally exited, a fresh Native attempt passed the entry and Guest/SSH checks and stopped at the required Guest IPv6 consent, not the old compatibility error. Main menu and single-player remain unverified. Targeted verification: 26 Python migration checks, 23 service checks, 7 launch-state checks and one Debug build passed; no updater/Appcast/menu changes.
