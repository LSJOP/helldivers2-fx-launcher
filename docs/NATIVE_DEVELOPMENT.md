# Native development / Native 开发指南

先读根 AGENTS.md，再查 [功能索引](FEATURE_REGISTRY.md)、[开发状态](DEVELOPMENT_STATUS.md) 和 [交接](NATIVE_APP_DEVELOPMENT_HANDOFF.md)，核对当前代码和相关固定分支；以下历史说明不应覆盖当前源码。

## Source and build

- 从对应的 `dev/environment`、`dev/ui` 或 `dev/core` 继续开发并复用其工作区；先同步核对 main、保护其他工作区。临时分支须用户事先授权，发布从 main 打 Tag。未合并候选不等于 main 已实现。
- 当前为 Swift Native Core，CoreSnapshot/legacy-script 保留历史，不重新引入 Python Bridge。
- Apple Silicon / macOS 14+、完整 Xcode、Python 3 检查工具及固定 Sparkle SPM。使用 `bash native-app/script/build_and_run.sh --build-only` 仅编译。
- 详细 Release/测试命令、架构和候选边界见交接文档。旧阶段版本号和测试结果不代表当前构建。

## Fast Development Mode

- 按任务范围选最少有效验证。匹配版本、配置及运行路径的历史实机证据可复用。遇到非关键检查失败，记下警告并继续，涉及数据、凭据、许可、反作弊及外部安全机制的检查继续执行。
- 实机兼容性任务已授权的常规组件安装、版本切换和 Steam／图形参数修改可直接执行。确认工作盘和 Guest，保留原值和回退路径，使用官方或可核验的上游制品，每轮改变一个主要变量。复用现有工作副本、日志和缓存。遇到失败先查实际错误，再做针对性调整。
- 以验收范围内的实际功能为准。图形兼容性检查记录生效后端和设备初始化日志，再进入指定场景并实际操作。性能、联机和长稳按任务需要采集。纯内部文档改动检查内容和链接即可。
- Apply the same scope in English-language work. Reuse matching evidence, run focused checks, and proceed past noncritical warnings. Keep credentials, data, redistribution, anti-cheat and external safety protections. For authorized live compatibility work, preserve working settings, change one main variable at a time, and verify the requested live behavior.

## State, credentials and recovery

SwiftUI pages use one AppState, TaskManager and Swift Native Core services; the historical JSONL Python Bridge is not the current runtime. Views do not construct remote commands. Refresh reads local metadata only; explicit connect/inspect buttons perform identity-bound Guest access.

- Configuration: `~/Library/Application Support/Helldivers2FXLauncher/settings.json`. The editor records the revision, preserves existing unknown fields and backs up before atomic replacement.
- Native diagnostics/reports: `~/Library/Application Support/Helldivers2FXLauncher/native`. Original Core recovery records can also be stored below the selected old launcher directory.
- SSH password, private-key passphrase and Guest sudo password default to session memory. They use controlled stdin/PTY, not argv/environment/password files. Passwords are never report content.
- Optional remembering stores SSH and sudo secrets independently in an installation-local AES-GCM file under Application Support after an actual challenge and verified Guest identity. Storage is bound to executable/digest, SSH endpoint and role, with private directory/file permissions; it does not use Keychain. Private-key passphrases remain session-only.
- Rejected or forgotten values are not silently reused; storage errors remain visible. Neither old script credentials nor signing keys are migrated or deleted. Restoring saved data does not prove a live authenticated session.
- Preferences contain non-secret options/metadata. Language and appearance preferences persist; standard macOS menu language may require restart.
- Cancellation does not force-stop already started FX/Steam/game processes and cannot prove that an in-flight transaction was unwritten. Inspect actual state and retained recovery records before retry/restore. Never restore Guest changes while gameplay is active.

## Evidence and limits

The earlier recorded dedicated FX 1.9.4 environment reached the main menu/controllable ship with explicit user confirmation on 2026-11-03. This is separate from current GUI-action acceptance, other FX versions, performance validation, independent EAC acceptance, ground missions and multiplayer. Fresh connection testing was blocked by another running FX copy; no instance was forcibly terminated.

Historical task-queue acceptance included nine inference checks and 35 migration checks, Debug builds and a six-page real-hardware smoke. That read-only baseline is superseded by the separately committed performance V2 scoped writer/restore backend; live adoption remains unverified. [Parameter audit](GAME_PERFORMANCE.md) · [Migration evidence](FUNCTION_MIGRATION.md).

The ten locale resources are zh-CN, en, ja, ko, ru, es, de, fr, pt-BR and zh-TW. Static coverage does not establish naturalness or every dynamic string. Signed-release availability, actual installation and recovery remain separate evidence: [Native updates](NATIVE_UPDATES.md).

## Documentation and resume

Maintain equivalent `README.md` / `README.zh-CN.md` with relative language links, per HD2_NATIVE_APP_UNIFIED_TASK_QUEUE v1.0.0. Homepage organization takes inspiration from [FlClash](https://github.com/chen08209/FlClash); no FlClash brand assets or copy are used.

Current screenshots reuse `docs/images/en/` and `docs/images/zh-CN/`, with actual Native Debug window captures for all six pages plus performance actions/software update. English/Chinese READMEs reference only their own language directory. Source/build/date, hashes, privacy scope and visual review are recorded in [image provenance](images/README.md) and `docs/images/manifest.json`. Legacy flat files are historical and are never referenced as current screenshots.

For every new page/important setting/launch/performance/update UI change, review ten-language strings, both READMEs, corresponding images and documented capabilities together. Capture the target language in the real App, inspect text and sensitive data, then update the manifest. If real capture is unavailable, record missing/pending images explicitly; no generated UI or cross-language fallback. Run `python3 -I -B native-app/script/check_readme_screenshots.py`; Native checks include it automatically. It checks paths/language directories/hashes, not the image language itself. Visual review is mandatory.

`.codex/task-queue.json` and `.codex/*progress.md` are historical task evidence, not current rules or an automatically waking queue. The registry, status and handoff are the shared current records; check actual Git/source before resuming.

中文要点：沿用固定功能分支和共享进度；CoreSnapshot 保持历史指针。凭据默认会话内存，可选按目标和角色绑定的本地 AES-GCM 保存，不使用 Keychain。取消后核对真实状态，不能把进程／主菜单／EAC／联机当作同一证据。性能操作保留安全门槛，实机效果仍需验收。中英文 README 同步维护，历史断点不会自动唤醒 Codex。

## Archive access retained from the earlier main README

The complete terminal launcher remains in [legacy-script](https://github.com/LSJOP/helldivers2-fx-launcher/blob/legacy-script/README.md), with a [script archive ZIP](https://github.com/LSJOP/helldivers2-fx-launcher/archive/refs/heads/legacy-script.zip). Existing local script installations are not changed. Old main ZIP/raw-main script URLs now refer to Native content; use legacy-script for the original script paths. The pre-migration [0205aca commit](https://github.com/LSJOP/helldivers2-fx-launcher/tree/0205acaec3b32024df180a6dfb8ecc587e2f1914) remains accessible. No old release or tag is deleted by this merge. The earlier main README's Phase 1 disabled-launch/five-page claims are superseded by the verified current source, not retained as current capabilities.

原终端脚本、ZIP 和历史提交入口保持有效；旧 main.zip／raw-main 路径现为 Native 内容，访问原脚本请改用 legacy-script。本次整合不修改既有脚本安装、不删除旧 Release 或 Tag。

## 更新包规则

后续补丁包可以采用新的归档规则，无需保证兼容 v1.0.1 的旧校验规则。发布前记录受影响的升级路径，必要时提供准确的安装方式，并继续执行当前签名、完整性和归档安全检查。
