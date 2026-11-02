# Game Performance / 游戏性能配置

Performance configuration instruction **v2.0.0**, 2026-11-03. The Native page now has a parameter-scoped preference editor, preview, explicit save consent, verified backup/read-back and conflict-guarded restore. Saved preferences are **not** effective Guest configuration or a performance benchmark. Historical M4 Pro / 24 GiB values remain reference records. Stable-profile management is deferred; nothing is automatically labelled stable.

## Audited mechanism

Original pinned Core: `launcher-20261026/performance_profile.py` reads/writes `defaults` domain **es.fxgam.steamac**; `goal-dxmt-20261026/start-hd2.py` verifies the fixed profile and passes `--cpus 8 --mem 8192 --vulkan-driver kosmickrisp --cmdline '… steamac.gpu_mib=6144'`. That broad configure-only backend can change Guest configuration and is deliberately not used by this editor. No CoreSnapshot/submodule/legacy-script changes.

Upstream FX 1.9.4 source commit **87bdb91f76a59f944898a01d1b6cad3d3270bf7d**, under `host/launcher/Sources/steamac-vm/`:

- [Settings.swift](https://github.com/fxgl/steamac/blob/87bdb91f76a59f944898a01d1b6cad3d3270bf7d/host/launcher/Sources/steamac-vm/Settings.swift): UserDefaults domain, known keys, next-start semantics, live display settings and driver enum. Domain's backing file is `~/Library/Preferences/es.fxgam.steamac.plist`; Native uses the system CFPreferences API rather than editing that daemon-owned file.
- [Options.swift](https://github.com/fxgl/steamac/blob/87bdb91f76a59f944898a01d1b6cad3d3270bf7d/host/launcher/Sources/steamac-vm/Options.swift): CLI takes precedence; CPU validation 1–255; CLI memory >=256 MiB, saved positive memory normalized to >=1024 MiB. No custom-memory alignment constraint was found there.
- [VMSizing.swift](https://github.com/fxgl/steamac/blob/87bdb91f76a59f944898a01d1b6cad3d3270bf7d/host/launcher/Sources/steamac-vm/VMSizing.swift): automatic CPU/memory rules, host reserve max(3072 MiB, 25% physical RAM), GPU working-set budget. Automatic ranges are not hard upstream custom limits.
- [Renderer.swift](https://github.com/fxgl/steamac/blob/87bdb91f76a59f944898a01d1b6cad3d3270bf7d/host/launcher/Sources/steamac-vm/Renderer.swift): MetalFX spatial scaler requires `supportsDevice` and only scales when output dimensions exceed input.

Only **1.9.4 plus executable SHA-256 matching the existing Core pin** is writable. Same version with another binary, other versions, missing fields and malformed preferences fail closed. The editor targets the same selected, archive-validated runtime and dedicated FX copy as the existing Native backend; it does not guess another installation.

## Parameters and conservative Native policy

| Parameter | Native editing | Limits / effects |
| --- | --- | --- |
| Virtual CPU count | Yes | Integer 1…min(255, physical CPU cores). This is a Native resource cap inside the confirmed upstream 1…255 range, not an optimal-performance recommendation. |
| Guest memory | Yes | Integer MiB; 256 MiB steps; 4096…min(16384, floor((host MiB − max(3072, host MiB/4) − 6144)/256)×256). The 4096 floor/16384 ceiling and alignment are conservative Native policy, not upstream custom constraints. A 24 GiB host permits 4096–12288 MiB. Unsupported host capacity is rejected. |
| Vulkan driver | Yes | Upstream enum `moltenvk`, `kosmickrisp`; offer only corresponding packaged dylibs and supported OS (15+, 26+ respectively). Library presence does not prove game compatibility. Shader caches may rebuild. No promised speedup. |
| Metal performance HUD | Yes | Boolean. Upstream FX observes its own settings live, but this external writer requires FX stopped. Saved value is loaded at the next FX start. Does not improve performance. |
| MetalFX super resolution | Read-only | Real upstream implementation confirmed; this editor does not yet probe `supportsDevice`. Key existence alone does not enable editing. |
| GPU budget | Read-only, 6144 MiB reference | Original command-line `steamac.gpu_mib`, used by host renderer and Guest reported budget; not an independent UserDefaults setting or an allocation cap. No automatic increase. |

Missing source values are not silently filled from defaults. Upstream automatic defaults (absent CPU/memory keys) follow `VMSizing`; driver default follows availability; HUD/super resolution default false. This first editor requires all five existing values to be readable and within its supported policy, so unsupported/partial configurations remain read-only.

**Original launch limitation:** the unchanged game launch command overrides CPU, memory and driver preferences. Its fixed-profile preflight can reject custom values before launching. Restore the backup before using that path. This task does not loosen launch guards or change the known working command. Merely restarting Guest inside an existing FX process does not establish adoption; FX must read settings afresh, and CLI overrides still win.

## Apply, backup and restore

1. Read hardware/current preferences; select the existing runtime through the existing FX UI; read editable configuration. Current, edited, last-applied, backup and effective states remain separate in AppState/backend snapshots. Effective is always unverified here.
2. Edit, then preview. Backend validates build/host/parameters and requires a stopped FX. The preview binds exact before/after, whole-domain revision, FX version and restore mode into a SHA-256 token. Cancel has no write or backup side effects.
3. Explicit confirmation invokes a serial transaction with a private nonblocking lock. Recheck revision and processes, create and read-verify a 0600 SHA-256 checked receipt, then recheck immediately before writing.
4. One `CFPreferencesSetMultiple` changes only the five owned keys; CFPreferences synchronization/read-back verifies the complete expected domain. Unknown fields remain untouched and are **not copied into backups**, which may otherwise leak credentials. System preference APIs retain ownership of plist format/permissions/metadata. No forced cfprefsd reload or direct daemon-owned plist replacement.
5. Receipts live in the existing App data directory under `native/performance-v2`, private 0700 directory, timestamped original receipts plus `last.json`. They record owned values, FX version, source, creation time, integrity hash and saved-not-effective validation status; no passwords. Receipt files use temporary-file + fsync + atomic replacement.
6. Restore previews the verified last successful save's actual before-values, requires current revision equal to the save's after-revision, creates another protective receipt, then uses the same writer and read-back. External changes to any domain field block restore. Corrupt/missing/unsupported backups cannot restore. Successful restore consumes the one-level restore availability; historical receipts remain.
7. On a failed write/read-back, automatically restore only if the whole observed domain exactly matches this operation's expected after-state. If external changes are visible, preserve them and report conflict. Failed rollback is never reported as success. Cancellation may leave a prepared receipt; re-read actual state rather than infer success.

CFPreferences provides synchronization, not an OS-wide compare-and-swap lock against arbitrary third-party writers. The private lock serializes Native operations; whole-domain checks and refusing any running FX reduce races. A malicious or uncooperative writer in the very small check/write interval cannot be excluded. Detected conflicts fail visibly, and are never forcibly overwritten during recovery.

## Running-state protection and UI

Read-only bounded process enumeration rejects any local `steamac-vm`, `gvproxy`, `gvproxy-eim` or `krun`, including foreign FX copies. Probe errors/empty output block writes. For this supported local VM topology, Guest Steam/game require that VM; their independent runtime state is not asserted. No SSH, process stop, restart, EAC, network or game-file operations occur. Detached/nonstandard VM topologies are outside the writable support scope.

Five tactical panels: hardware, saved current values, reference evidence, parameter editor and apply/restore. Advanced fields collapse by default. Preview/confirmation shows real changes and launch limitations; operation events show checking, backing up, applying/restoring, saved/unverified or failure. User-facing errors are localized; diagnostic codes are collapsed. New strings cover all ten original languages; English fallback does not count as translation.

Current English/Chinese README screenshots now show the real performance page and gated action area in their own language directories; provenance is in `docs/images/README.md`. No generated UI screenshot is used. No real FX configuration was modified for automated testing. Fixture tests include a fresh isolated CFPreferences domain; live game performance, actual Guest adoption and human GUI acceptance remain NOT_TESTED.

本次新增限定参数的安全保存与备份恢复：先读取、编辑、预览并确认，再校验备份、写入和重新读取。真实 FX 运行时禁止保存；不停止或重启任何进程。CPU、Guest 内存、实际可用 Vulkan 驱动和 Metal HUD 可编辑；超分辨率与 GPU 预算保持只读。原启动路径有固定参数和预检，自定义值可能被拒绝，使用该路径前应恢复备份。「已写入」始终不等于 Guest 已生效或游戏性能提升。
