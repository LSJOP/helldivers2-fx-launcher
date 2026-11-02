# Function migration — HD2_NATIVE_APP_FUNCTION_MIGRATION_v1.0.0

Baseline: pinned `legacy-script` commit f6dfb4c (original launcher 0205aca; separate Native metadata snapshot). Archive content is not modified. Status describes actual Native/backend wiring and evidence, not game compatibility.

| Legacy capability / source | Native scope | Status |
| --- | --- | --- |
| Entry/menu `Start.command`, `menu.py:menu` | Five SwiftUI pages; preserve native navigation | 已迁移 |
| Host/FX metadata `dependencies.py`, `dependency_discovery.py` | Real bounded metadata and full discovered paths; process/runtime claims require the separate explicit inspection | 已迁移 |
| Launch/runtime dependency guards `dependencies.inspect_runtime` | Explicit detailed inspection, configured legacy root; no auto Node execution on refresh | 需要进一步验证 |
| Game launch `start-hd2.py:main`, `launch_safety.Session` | Explicit operation, original hashes/target lock/consent/rollback; no development-time live launch | 需要进一步验证 |
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
| Update check/channel/notes `update_checker.check` | Read-only official release query; no install | 部分迁移 |
| Automatic update install | Original `INSTALL_ENABLED=False` | 不适用 |
| FX version switching | Original archived menu has no selection/switch implementation; metadata snapshot is not proof of such a legacy UI capability | 不适用 |
| Ten locales `i18n.LANGUAGES`, `locales/*.json` | zh-CN, en, ja, ko, ru, es, de, fr, pt-BR, zh-TW; preserve catalogs; Native-only text coverage tracked separately | 部分迁移 |
| Help/changelog/folder `help_center.py`, `menu.instructions` | Native help/catalog/report entrypoints; archive remains accessible | 部分迁移 |
| Terminal ASCII emblem/layout/intro/TTY | Archive-only presentation; Native tactical theme replaces TTY behavior | 不适用 |

Live FX/Guest/SSH/Steam/EAC/multiplayer success remains unverified until an explicit user operation produces fresh evidence. Fixture checks must not be described as a live-game launch. Unknown configuration fields must be preserved; legacy `preferences.save` alone discards them, so Native uses validated merge plus optimistic conflict checking and backup. Large runtime assets are not installed or moved. No archive source is rewritten.

Current focused evidence: Xcode Debug build passed; 18 protocol/metadata checks, 14 isolated migration checks and 21 service checks passed. One bundled-App smoke passed catalog discovery (20 operations), all ten original locale resources, real read-only configuration access and launch rejection without consent/runtime root. Static audit guard confirms automatic metadata operations cannot write, execute processes, connect networks or access SSH/Keychain/settings. No real launch, SSH, system network change, performance write or multiplayer acceptance was performed. New Native translations remain partial, with explicit English fallback.
