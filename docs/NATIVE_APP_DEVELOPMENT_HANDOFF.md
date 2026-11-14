# HD2FXNative 接续开发交接

更新：2026-11-14（Asia/Shanghai）。先读 [AGENTS](../AGENTS.md) 和 [当前状态](DEVELOPMENT_STATUS.md)。本文件是接续入口，不是另一套任务队列。

## Git 基线和接续位置

最后已知 main Commit SHA：`478d2bfdf0b75b92aaaf7516e5ddcd10d03309af`。本次文档基于该提交，不含未验收的整合代码。main 后续 SHA 必须运行 `git fetch --all --prune`、`git rev-parse origin/main` 获取，失败则保留“最后已知”，不可当作最新远端。

当前文档交付的 commit：`git log -1 --format='%H %s' -- docs/NATIVE_APP_DEVELOPMENT_HANDOFF.md`。合并归属：`git merge-base --is-ancestor <文档提交> origin/main`。这避免向同一提交写入自身 SHA 的循环；最终合并/推送 SHA 以 Git 为准。

候选分支 `integration/native-app-consolidation` 本地 `41af2ef`；构建来源 `cd27baa378f3fedb09153c1468bc6a03bbdefb26`，0.1.0 arm64/ad-hoc。不得从候选报告反推 main 已有功能。其他活动分支/脏工作区及备份位置见开发状态。不要切换、stash 或覆盖别人的 Worktree；使用独立任务分支。

## 架构与关键模块

| 路径 | 职责 |
|---|---|
| native-app/App、Views、Models | SwiftUI 页面/主题/导航/模型，窄范围 AppKit 原生交互 |
| native-app/Stores/AppState.swift | 唯一业务状态所有者；首次配置/启动接续应共用服务，不能在视图再建部署流程 |
| native-app/Services/TaskManager.swift | 原生任务执行/状态；历史 Python Bridge 不代表当前执行路径 |
| native-app/Core/NativeCoreService.swift | allowlist 原生操作分派与流程入口 |
| Core/FXDiscoveryService.swift、LaunchService.swift、GuestService.swift | FX 发现/身份、启动和 Guest 会话 |
| Core/SSHTransport.swift、Services/SessionCredentialManager.swift | SSH、分角色凭据、失败脱敏和身份边界 |
| Core/EnvironmentDeployment.swift、EnvironmentAdapters.swift、ComponentDeploymentAdapters.swift | 环境模型、预检、计划、部署回执、备份与恢复 |
| Core/ConfigurationService.swift、PerformanceConfigurationService.swift、SteamOSNetworkService.swift | 配置版本/原子更新、性能及独立网络事务 |
| Services/AppUpdateManager.swift、UpdateReleaseService.swift | Sparkle 与 GitHub 版本/签名下载；候选另有 UpdateHelper 安装归档预检 |
| Resources/native-locales.json、Localization | 十语言界面/系统菜单资源；十语言 bundle 品牌扩展尚在候选 |
| checks、script | 隔离 fixtures、构建、本地化、更新和包结构检查 |

CoreSnapshot 固定指向 legacy-script，保留不修改。当前 Native App 不应重新打包/执行旧 Python Core。main 当前凭据仅内存；LocalCredentialStore.swift 在候选中，不能引用它作为 main 构建输入。旧阶段报告中的加密/Keychain/内存策略须结合实际源码和当前 AGENTS 优先级解释。

## 构建方式（仓库根目录）

要求 Apple Silicon、macOS 14+、完整 Xcode/macOS SDK、Python 3（用于检查/资源脚本）、固定 Sparkle SPM 依赖。

```sh
bash native-app/script/build_and_run.sh --build-only
bash native-app/script/run_checks.sh
bash native-app/script/run_update_checks.sh
python3 -I -B native-app/script/check_localization.py
python3 -I -B script/check_docs.py
python3 -I -B native-app/script/check_readme_screenshots.py
```

Debug：native-app/build/Debug/HD2FXNative.app。默认 run 模式会打开 App；仅验证编译使用 --build-only，不启动游戏。run_update_checks 要先完成构建以解析 Sparkle。检查脚本中实际文件存在性优先于旧命令。

干净提交后构建 arm64 Release，输出必须是新的绝对目录，不覆盖旧包：

```sh
bash native-app/script/build_local_release.sh /absolute/new/output-directory
```

脚本执行 ad-hoc 签名、包结构检查并写 SOURCE-COMMIT.txt 和可执行文件 SHA-256。DMG/ZIP 分别计算哈希，不将可执行文件 hash 当作 App 整体或 DMG hash。候选新增 package_internal_dmg.sh，main 当前无该入口。正式签名 feed、发布、Developer ID/公证均是独立事项，不由本命令完成。

## 已有结果和待办

测试计数、范围、失败项集中在 [开发状态](DEVELOPMENT_STATUS.md#测试证据与局限)。候选完整门禁并未通过，不能沿用历史测试跳过本次改动的检查。本次文档任务不重编译 App，因没有代码或用户界面改动。

下一位开发者的第一项任务：fetch/确认远端、保护脏工作区，然后继续候选独有差异审查和十语言截图门禁；禁止直接合并全部分支。其后完成可信更新闭环和隔离故障恢复测试，再按授权进行用户实机验收/主线晋级。网络失败、缺失截图或高风险未决问题要记为阻塞，不用聊天中的“完成”代替证据。

## 每次任务收尾

1. 按变更运行必要检查，记录命令、结果、所用源码 commit 和范围；失败保留真实错误。
2. 同步状态、交接、必要的双语说明/十语言及截图；历史报告只链接，不复制为新任务清单。
3. diff/秘密检查后仅提交本任务文件；用 Git 查询提交 SHA，安全晋级 main 并普通推送，验证远端包含关系。
4. 报告完成/阻塞/待实机验收、交付源码 SHA 和明确下一项任务。推送失败不能说已上 GitHub。

本次文档验证：双语文档检查 15/15、14 个截图引用的路径/来源/hash 检查、当前入口本地链接检查与 git diff --check 均通过。未更改 UI/本地化资源，未重编译 App。fetch GitHub HTTPS 连接超时；远端更新未确认，必须在网络恢复后重新 fetch/核对并普通推送，不得声称已上 GitHub。
