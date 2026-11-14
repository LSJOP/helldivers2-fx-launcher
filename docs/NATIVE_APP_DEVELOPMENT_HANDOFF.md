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

## 本轮补充交接：已核对的本地 main 与候选

本轮开始时本地 main 为 `3e0539db51da2a432983711cfe33297d45a3562d`（只含长期状态文档更新）；最后已知远端 main 仍为 `478d2bfdf0b75b92aaaf7516e5ddcd10d03309af`。不得把本地 main 称为已推送的最终 main。当前代码整合尚未满足晋级条件。

本轮重新执行 `codesign --verify --deep --strict` 检查上一轮 arm64 Release App，通过；SOURCE-COMMIT 为 cd27baa。没有重新构建或将该包冒充新 main 构建。App 路径：`绝地潜兵脚本/APP 版本/Consolidation-20261114-cd27baa/HD2FXNative.app`。版本 0.1.0。DMG SHA-256：`f4ba6d22b12c8e0a79bc60b10e1f5fc723b40b7e8921d05bc3a64eb671b97551`。

### 模块交付边界

| 模块 | 已完成/现有实现 | 未完成与验收 |
|---|---|---|
| FEX | main 有能力探测、审核部署/回执恢复；候选加强 helper 注册及启动前重探测 | 官方/自定义 FEX、新 Guest、部署失败/恢复真实矩阵待用户实机验收 |
| 首次配置 | main 有计划/执行/恢复；候选共享首页配置服务与自动接续 | 全新环境和重复执行/取消/重连待实机；完整门禁未通过 |
| SSH/sudo | 独立角色、身份/boot 绑定、stdin 传密和脱敏；候选保留独立 sudo 与隧道隔离 | 不同密码、认证失败、身份漂移待用户实机验收 |
| 凭据 | main 仅内存；候选 AES-GCM store 有隔离测试 | App 重启、更新/忘记/拒绝、目标变化实机验收未完成；无 Keychain |
| 自动更新 | main GitHub/Sparkle；候选 SHA/Ed25519/归档路径与安装元数据绑定、进度和 feed 修复 | 公钥/feed 生产配置、失败回滚/安装/重启端到端待完成；不降低验证 |
| 品牌/十语言 | main 有十语言，候选有十语言 bundle 品牌；静态检查通过 | 真实 Finder/菜单/页面截断/自然度和截图来源门禁待验收 |

### 尚未整合/必须保留的分支

| 分支 | 保留原因 |
|---|---|
| integration/native-app-consolidation (`41af2ef`) | 核心候选，完整门禁未过，未确认推送 |
| release/v1.0.0-integration (`267a2b5`) | 主要实现来源，路径整合不代表全部历史/独有内容完成审查 |
| feature/native-recovery-20261112 (`64141fa`) | 有部署/实机历史与脏成果；候选仅补入确认的独有探测 |
| feature/localized-app-brand-20261114 (`6e93460`) | 候选已挑入品牌实现，main 未含该功能，尚有活跃 Worktree |
| development (`c8cfa5a`) | 脏暂存成果和独有测试/实现尚未全部审查 |
| docs/v1-release-preparation-20261113 (`c8cfa5a`) | 脏更新 UI/十语言/文档成果仍有差异 |
| docs/native-development-state-20261114 | 已在本地 main，远端未确认，有活跃 Worktree |
| docs/native-handoff-final-20261114 | 本轮规范清理和接续交接成果；按最终 Git 包含关系确认整合 |
| legacy-script | 必须保留的原脚本历史/固定 submodule 来源 |

其余远程分支是否进入最后已知 main 的清单，见候选 consolidation 报告；祖先关系不等于可删除，仍须查活跃 Worktree/聊天依赖。本次不删除任何远程分支。

本轮按工作区实际字节与候选比较：development 5 个已修改文件相同、22 个不同；recovery 2 个相同、6 个不同；release-preparation 0 个相同、19 个不同（仅已跟踪修改，不含未跟踪文件）。这些数量只是后续复核入口，差异不自动表示候选缺失功能。备份已保存，禁止直接覆盖。

### 可直接执行的优先级与验收标准

1. **P0 远端同步与成果保护**：fetch 成功、核实真实 main SHA；逐项检查差异和所有未跟踪文件。验收：每项独有代码标明复用/替代/待完成，原改动可恢复，无秘密入库。
2. **P0 候选截图门禁**：从实际候选构建采集所需十语言 UI，核对 Finder/菜单/设置/首次配置/更新错误文本与裁剪。验收：真实视觉审阅和 provenance 完整，原始 run_checks 不跳过截图检查通过。
3. **P0 更新故障测试**：以隔离 App/临时目录测试受信签名、错误 hash/signature、恶意路径、安装失败与回滚/重启。验收：所有失败拒绝安装或恢复原包；无签名关闭、无真实系统替换。
4. **P1 发布候选验证**：受影响 Swift/Python隔离测试、本地化、文档和新 arm64 Release 一次验证。验收：全部必要门禁通过，源码/版本/资源/签名/hash 一致；未获授权的实机项目仍标 pending。
5. **P1 主线晋级**：在最新 main 上验证集成，不混入其他脏成果。验收：无冲突/高风险未决项，普通 push 成功，ls-remote SHA 与本地 main 一致，交接和代码同一次交付。
6. **随后用户实机验收**：按 FEX、首次配置、双角色密码、IPv6、性能、菜单/单人/多人分别记录结果。任何一项未执行都不标已验收。
