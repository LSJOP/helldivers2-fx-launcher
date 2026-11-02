# Native development / Native 开发指南

## Source and build

- Native mainline: `main` now integrates the completed Native snapshot. `feature/macos-native-app` is retained; safely synchronize it with main before reuse. UX v2.1.0 remains deferred; future work should start from latest main in a separate worktree, suggested branch `feature/native-app-ux-v2`. No scheduling was configured.
- Pinned archive: `native-app/CoreSnapshot` (`legacy-script`); original Core version `0.1.0-preview.4`. Native bundle version is `0.1.0`, build `1`, from the Xcode project. Neither is a published Release claim.
- Apple Silicon / macOS 14+, complete Xcode and macOS SDK, Python 3.9+. Clone with `--recurse-submodules`; source ZIPs omit Core.
- Build/run: from `native-app`, use `./script/build_and_run.sh --xcode-only`, then open `build/Debug/HD2FXNative.app`. The build packages selected archived Python/locale sources; it does not install FX or download runtime/game/Guest images.
- Source-level isolation and targeted checks live under `native-app/checks`. Use `script/run_checks.sh` only when a full local suite is appropriate; UI/documentation tasks normally need narrower checks. See [AGENTS.md](../AGENTS.md).

## State, credentials and recovery

SwiftUI pages use one AppState, TaskManager and supervised JSONL Bridge. Views do not construct remote commands. Refresh reads local metadata only; selecting Game Performance can read host hardware and stored FX preferences. Explicit connect/inspect buttons perform identity-bound Guest access without starting it or changing Guest configuration.

- Configuration: `~/Library/Application Support/Helldivers2FXLauncher/settings.json`. The editor records the revision, preserves existing unknown fields and backs up before atomic replacement.
- Native diagnostics/reports: `~/Library/Application Support/Helldivers2FXLauncher/native`. Original Core recovery records can also be stored below the selected old launcher directory.
- SSH password, private-key passphrase and Guest sudo password default to session memory. They use controlled stdin/PTY, not argv/environment/password files. Passwords are never report content.
- Optional remembering saves SSH and sudo independently to `com.lsjop.helldivers2fx.native.remembered-credentials.v1` after actual password-challenge success. Accounts are scoped by selected target/config revision. Private-key passphrases remain session-only.
- Automatic reads forbid Keychain authorization UI. Locked, unavailable or access-restricted storage falls back to session input. Explicit settings access or changed App identity/signature can still require system authorization. Invalid stored credentials stop reuse until updated. Clear operations require confirmation and touch only this new App service; old script, signing and Sparkle items are untouched.
- Preferences contain only non-secret options/metadata. Language and Python interpreter persist; appearance is session-only. A target can be remembered after opted-in credentials are saved. Restart to apply the chosen language to standard macOS menus and Sparkle UI.
- Cancellation does not force-stop already started FX/Steam/game processes and cannot prove that an in-flight transaction was unwritten. Inspect actual state and retained recovery records before retry/restore. Never restore Guest changes while gameplay is active.

## Evidence and limits

The earlier recorded dedicated FX 1.9.4 environment reached the main menu/controllable ship with explicit user confirmation on 2026-11-03. This is separate from current GUI-action acceptance, other FX versions, performance validation, independent EAC acceptance, ground missions and multiplayer. Fresh connection testing was blocked by another running FX copy; no instance was forcibly terminated.

Nine new performance inference checks and 35 migration checks passed, along with Debug builds and the six-page real-hardware smoke. Inference remains read-only because no validated portable tuning bounds or scoped restore backend exist. [Parameter audit](GAME_PERFORMANCE.md) · [Migration evidence](FUNCTION_MIGRATION.md).

The ten original locale catalogs are zh-CN, en, ja, ko, ru, es, de, fr, pt-BR and zh-TW. Native-only translations are partial; missing strings fall back to English. Sparkle code integration is separate from signed-feed/release/installation acceptance: [Native updates](NATIVE_UPDATES.md).

## Documentation and resume

Maintain equivalent `README.md` / `README.zh-CN.md` with relative language links, per HD2_NATIVE_APP_UNIFIED_TASK_QUEUE v1.0.0. Homepage organization takes inspiration from [FlClash](https://github.com/chen08209/FlClash); no FlClash brand assets or copy are used.

Screenshots in `docs/images/` were captured from the actual Debug App window on 2026-11-03 during task-queue acceptance, after reading real hardware/preferences. They are proportionally reduced only. They contain no entered credentials or personal paths. Older Logs/Settings captures remain historical and are not used to represent this iteration's interface.

`.codex/task-queue.json` and `.codex/progress.md` persist task evidence and resume points. They do not wake Codex automatically. Check actual Git/source before resuming; completed tasks must not be regenerated. No scheduled continuation was created.

中文要点：开发分支继续沿用，Core 固定且不修改；普通刷新仅本机元数据，性能页读取硬件／偏好，Guest 检查需主动点击。凭据默认内存、可选独立 Keychain 保存；原脚本钥匙串项目不动。取消后需核对真实状态，不能把进程／主菜单／EAC／联机当作同一证据。性能写入／恢复尚不可用。中英文 README 同步维护，断点文件不会自动唤醒 Codex。

## Archive access retained from the earlier main README

The complete terminal launcher remains in [legacy-script](https://github.com/LSJOP/helldivers2-fx-launcher/blob/legacy-script/README.md), with a [script archive ZIP](https://github.com/LSJOP/helldivers2-fx-launcher/archive/refs/heads/legacy-script.zip). Existing local script installations are not changed. Old main ZIP/raw-main script URLs now refer to Native content; use legacy-script for the original script paths. The pre-migration [0205aca commit](https://github.com/LSJOP/helldivers2-fx-launcher/tree/0205acaec3b32024df180a6dfb8ecc587e2f1914) remains accessible. No old release or tag is deleted by this merge. The earlier main README's Phase 1 disabled-launch/five-page claims are superseded by the verified current source, not retained as current capabilities.

原终端脚本、ZIP 和历史提交入口保持有效；旧 main.zip／raw-main 路径现为 Native 内容，访问原脚本请改用 legacy-script。本次整合不修改既有脚本安装、不删除旧 Release 或 Tag。
