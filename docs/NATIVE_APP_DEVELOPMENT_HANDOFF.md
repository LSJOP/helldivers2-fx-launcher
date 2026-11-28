# HD2FXNative 接续开发交接

> 2026-11-28 · v1.1.0（2026112801）从 `main` 发布。DX11 仍需主动授权，批准的 RF FEX 和 Proton-JE 随包分发，Steam 和 FX 各自管理其 Runtime 与图形组件。沿用正式 Ed25519 信任根。升级和包验收与已归档的游戏实机记录分开。[发布流程](NATIVE_UPDATES.md) · [成功环境与验收](environment/HD2_SUCCESSFUL_ENVIRONMENT_BASELINE.md)

> 2026-11-28 · `dev/core` 的 FX 1.9.15 DXMT 候选通过同盘双向切换。切换通过宿主与 Guest 收据保护原路径，关闭后只恢复已管理的配置。继续开发前核对候选提交、实际渲染链、声音与已知限制，复用存档和原测试盘。[成功环境与验收](environment/HD2_SUCCESSFUL_ENVIRONMENT_BASELINE.md)

> 2026-11-27 · FX 1.9.9 功能等效母本已恢复并两次核对完整 SHA-256。正式 v1.0.7 复现 Steam 确认框及 Swift/Python 的 Runtime 路径转义错误。main 的 `c686f7b` 修复并发布 v1.0.8。正式首配、Guest 和 App 重开后的复用、从干净副本首页启动、游戏窗口与菜单、单人与四人实际落地、EAC 与 v1.0.7 组件级增量升级均通过。证据、差异与未验收事项见[基线验收](testing/FX199_FRESH_USER_BASELINE.md)。

> 2026-11-27 · 从 PR #23 已有 Worktree 续接。Debug / Release 用同一个组件事务。RF 备用资源从同版本 Ed25519 签名更新清单获取；正式包只包含 App Core、RF FEX、Proton-JE，Steam 管理 Runtime 4。v1.0.7 已从 main 发布为 Stable / Latest。正式 v1.0.4 实际升级并自动重启成功。正式 v1.0.5 和 v1.0.6 在本机因 dyld 的 Sparkle 库验证无法启动。下一次首装实机必须从已核验的 FX199_FRESH_USER_BASELINE 恢复工作副本。历史 FX 1.9.12、FX 1.9.9 原盘和现有离线备份均为受保护参考。见[基线验收](testing/FX199_FRESH_USER_BASELINE.md)。

v1.0.5 过渡发行保留受控 Debug 资源，仅公开分发签名更新引擎及获准内容。公开端点和实际升级证据以发行验收记录为准。

> 2026-11-22 · Dashboard V003 接续入口见[整合报告](Dashboard_UI_V003_Final_Integration_Report.md)。保留 main 的 1.0.4 业务和签名基础，真实 FX、Guest、SSH 和游戏仍需要独立实机验收。

环境分支已整合合并 PR #22 的远端 main，继续使用原有工作树。真实 RF 部署状态和合并冲突处理见[专项验收](testing/RF_FEX_BUNDLED_DEPLOYMENT_ACCEPTANCE.md)。

2026-11-24 复验从源码 `564d31274056a02dfdad5abfd4ad10a055625e97` 继续，已观察到独立副本的第二次正常启动。既有组件通过 App 检查。另修复首次配置完成后总览的启动按钮恢复逻辑。缺失修复、真实上传和分发审批仍待验收。


2026-11-26：v1.0.6 候选由 Guest Steam 负责 Runtime 4。保留历史归档作为本地证据，构建与打包拒绝已退役的 Bundle 目录。现有 Steam Runtime 和 ARM64 Runtime 保留。RF FEX 与 Proton-JE 公开分发审批仍独立待完成。

2026-11-26：v1.0.7 专项已完成权利/来源分层审核。RF 历史 41 文件保持原样作证；发布候选排除未证实授权的 `fex-compat-tool` 与未使用的 `unshare.py`，改为 39 个 FEX 文件 + 项目自有 wrapper + MIT 声明，新树指纹 `79c051c4…`。Proton-JE 对上游 Release SHA-256/SHA-512、标签提交及 62 个递归子模块已固定。RC 组装路径已加入；Stable 仍需同地对应源码制品、现有 Ed25519 私钥签名及真实 Guest/游戏验收。见 `docs/audits/*Redistribution_Audit.md` 与 `docs/acceptance/v1.0.7_Release_Readiness.md`。

2026-11-25（历史）：RF FEX、Proton-JE 和 SteamLinuxRuntime_4 统一内置优先。沿用 Proton 的完整树校验和 Runtime 的事务，保留原有 ARM64 Runtime。受控构建导入、大小、更新上限和验收见[专项报告](testing/RF_FEX_BUNDLED_DEPLOYMENT_ACCEPTANCE.md)。

组件级更新与 Guest 部署独立。协议、原交易机制、隔离测试方式和旧版限制见[更新文档](NATIVE_UPDATES.md#component-update-schema-3)和[验收](testing/COMPONENT_UPDATES_ACCEPTANCE.md)。

> **协作入口（2026-11-16）：** 从 `main`、`dev/environment`、`dev/ui`、`dev/core`、`legacy-script` 五种固定职责选择已有分支；共享规范归 `dev/core`。先查 [功能索引](FEATURE_REGISTRY.md)、开发状态、实际代码及对应分支/PR，再动手；每次开发、修复、测试或合并后更新索引和本交接，记录提交、范围、结果、日期与未完成项。不要为会话或发布创建新分支；临时分支须用户事先授权。保护已有工作树和未合并成果。

> 固定分支规范及历史分支分类由 `dev/core` 的 PR #18/#19 合入；2026-11-16 文档检查 15/15、相对链接、diff、敏感信息模式扫描和工作流 YAML 语法通过。未重跑 App 回归或实际触发工作流。首次配置及其他独有历史成果未自动迁移；后续按功能复核并记录。

> **当前入口（2026-11-16）：** 以 [功能索引](FEATURE_REGISTRY.md) 和当前 Git/代码为准。v1.0.4（2026111601）已按用户明确决定发布，PR #14 已合并，标签指向 `6987fae`；真实跨版本应用内升级、升级后自动重启及生产环境失败恢复均未验证。`fix/first-run-ssh-access` `c32ce24` 为未合入的开发分支，RF 实际打包、新镜像安装和许可待验证。以下 2026-11-14 章节为历史阶段记录；旧的“main 仅内存凭据”“无正式更新包/服务关闭”等判断不能用于当前主线。后续先核对远端和索引，再按范围更新索引与本交接。


> 2026-11-14：品牌与首页五卡 LED 已整合，状态矩阵及中英文真实 Debug 截图完成检查；真实 EAC／联机成功仍未确认。

> 2026-11-14 日志与启动候选：为启动流程记录有界脱敏事件、任务 ID、耗时及本地时间显示；失败隐藏旧进度。FX 1.9.9 的只读状态与日志更新已验证，日志与首次配置页双语截图已更新；完整启动/EAC/游戏画面尚待验收；以当前任务分支和测试结果为准。

更新：2026-11-14（Asia/Shanghai）。先读 [AGENTS](../AGENTS.md) 和 [当前状态](DEVELOPMENT_STATUS.md)。本文件是接续入口，不是另一套任务队列。

## 当前交付：品牌与首页 LED 整合（2026-11-14）

- 已通过系统代理 fetch，远端 main 基线 `a99e1d35e42cd5423372ba909f53ff18a538cae1`，确认应用更名已合入。独立 `integration/brand-led-20261114` 工作树无冲突挑入 LED 候选 `58df1a8`，保留其他工作树与未提交成果；脏工作树补丁及未跟踪归档位于 `Backups/brand-led-20261114`。
- 首页保留 FX、虚拟机、Steam、EAC、联机。共用可测试状态映射：绿色仅表示已观察的进程或通过 Guest 身份验证的连接；进行中黄色、明确阶段失败红色、缺少／过期证据灰色。EAC 与联机无独立成功探测，保持未验证；不从游戏进程、菜单或单人记录推断。修复英文虚拟机标题截断，复用十语言现有 VM 文案。
- 最终整合源码 arm64 Debug 构建通过；真实隔离窗口中英文各十张采集审核，README 引用十四张来源／哈希门禁通过。截图来自 Debug 0.1.0 (2026111401)，不是正式 v1.0.0 的截图。
- 专项验证：55 项首页状态矩阵、23 项启动／GUI 状态回归、十语言静态资源、8 项本地化负例、10 种 bundle／App 品牌一致性、11 项截图门禁负例、15 项文档检查；详见本工作树 `native-app/evidence/`。矩阵检查调用与真实视图相同的映射，属于隔离输入检查，未执行真实 FX／Guest／游戏验收。
- 双语 README／CHANGELOG、截图来源和十语言资源同步；改动归属 Unreleased。正式 v1.0.0 DMG、标签与 GitHub Release 未改动。源码提交及远端确认以最终 Git 输出和 `git log` 为准，不在文档中循环填入自身 SHA。
- 推送前再次 fetch 得到 main `b789642fdb4eadb1d80c6578409e2a5044436fcb`（含同一 LED 候选及 8 项优先级检查）。合并保留远端历史；使用本轮 55 项共享证据映射矩阵替代较窄检查，保留已审核截图及双语页面展示。最终 App Swift／本地化资源与本轮已构建、采集的源码字节一致。其他活动工作树继续原地保留，本轮未写入。
- 待用户实机验收：EAC 加载、多人联机、真实运行状态变化和自动更新完整闭环；下一步仅在明确授权后测试对应项目。历史章节是阶段记录，以本节与最新 Git 为本轮进度。


> 最新远端核验：本轮 `git ls-remote origin refs/heads/main` 已确认 main 为 `954f88e500efc3f59630ccba2968c53cf0405cc4`，状态管理/交接规则已成功推送。此后本文件仅追加本次同步结果；最终文档提交 SHA 用 `git log -1 -- docs/DEVELOPMENT_STATUS.md docs/NATIVE_APP_DEVELOPMENT_HANDOFF.md` 查询并核对远端，避免自身 SHA 循环。
> `integration/native-app-consolidation` 的 `41af2ef890e10e7d636ef31205a4fc3c03845536` 也已普通推送 GitHub，作为候选备份，**尚未合并 main**。下文网络失败说明是先前尝试的历史记录，已被此次成功同步取代；其余截图/差异/更新闭环阻塞仍成立。


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

## 继续整合检查点（2026-11-14）

候选已合入 main `50f3ecae9fd545bc6aacbda6c4665f089db64feb` 的规则/文档，保留双方 README/CHANGELOG。新增安装边界缓存重验（SHA-256、Ed25519、ZIP 路径和拒绝符号链接），增加下载后篡改/链接测试。更新服务 39 项、更新管理 23 项及 ZIP 7 项隔离检查通过。未完成 Sparkle 实际替换/失败回滚/重启隔离闭环；不得将重验测试称为安装闭环完成。

已从当前候选新建 Debug 构建并启动隔离捕获副本，禁用凭据加载和 Guest 操作。捕获未产生请求，CUA getApp 接口 timeoutReached；截图未通过，不改写 provenance 或视觉 PASS。main 晋级继续阻塞。实际最新代码/构建提交通过 Git 和 SOURCE-COMMIT.txt 核对，cd27baa 仅保留历史。App 版本维持 0.1.0，构建号更新为 2026111401。

### 新候选交付与截图后续

最新 Release 源码 `4e104b7936fc20e2e7a5ef763f9ea4af6163525c`，0.1.0 (2026111401)，arm64，source_dirty=false。输出：`绝地潜兵脚本/APP 版本/Consolidation-20261114-4e104b79/HD2FXNative.app`，ad-hoc/资源/来源检查通过；不是 cd27baa 旧包，也不是已合入 main 的包。此前“未产生请求”的说明只适用于首次英文尝试：中文随后捕获成功，原图在候选 worktree `native-app/evidence/capture-resume-zh`，dashboard/settings 已视觉查看，其他图片及英文/其余语言尚未完成审阅。未改写截图 manifest。完整截图门禁依旧失败。

本轮更新测试已通过，不等于 Sparkle 安装/回滚/重启闭环通过。main 仍保持 50f3eca，整合尚未结束；候选已合入 main 的规则，AGENTS v1.2.20 本轮无需规则变更。下一步先解决英文捕获/全语言审阅，再完成真正隔离安装闭环和独有分支差异审查，不能继续以补文档代替这三项工作。

## 跨机器接续（2026-11-14）

以[跨机器接续检查点](DEVELOPMENT_STATUS.md#跨机器接续检查点2026-11-14)为本机最新证据。上一台电脑的 App/截图和未推送文件不位于本机；本机使用基线 `78a9eca` 的独立工作树。当前构建及 README 图片源码为 `8f4c396`，图片是实际隔离 Debug 窗口，Release 候选另行签名验包。

下一步：完成其余语言及 Finder/菜单/动态错误的目视审阅，逐项处置本机 full-audit 补丁并核对旧机独有未提交内容，再用只作用于临时 App 的签名 fixture 演练 Sparkle 替换、故障回滚和重启。确认这些门禁及完整运行检查后才能晋级 main。

最新验收增量：十语言大窗口常态页面截图已捕获并初审，原始全文检查退出 0；剩余视觉检查聚焦菜单/Finder、窄窗口、动态错误与翻译自然度。先以临时签名密钥和隔离 App 目录建立可重复的 Sparkle 成功/故障 fixture，明确目录保护和替换前后版本/进程证据；生产更新默认仍关闭。

## FX 1.9.9 实机进度（2026-11-14）

候选已通过 GUI 启动测试 FX 并通过 SSH，停在 App 的现有 FEX 来源确认，具体证据见[开发状态](DEVELOPMENT_STATUS.md#fx-199-测试机实机验收2026-11-14)。恢复严格的新用户测试需先正常关停测试 Guest，重新建立并验证冷态备份，再核对历史项目的当前归属，随后从 GUI 执行部署。保留兼容性探针的目标绑定和显式同意。Steam、游戏进程、主菜单、单人和多人继续独立取证。

FEX 核验现以同一文件树指纹串起预检、审核与实际探针。下一步需要针对测试 Guest 的可信 FEX 文件清单或经过审核的替换件，再继续 GUI 实机。此修复没有 UI 或本地化变更。


### FX 1.9.9 RootFS 启动排查

13:39 启动已生成指向 /usr/share/guestos/fex-mesa 的配置。测试 Guest 证实该目录的 provider 文件与 x86-64 loader 存在。失败子进程在 pressure-vessel 后报告 RootFS 为空。新增 Guest 侧先决条件检查及缺失 loader 回归测试，未改变真实 Guest 配置。下一步使用同一次启动中的容器内环境和实际 FEX 配置定位丢失点，完整游戏验收仍阻塞。此检查仅覆盖 SteamOS 默认 provider，不建立容器内就绪证据。

FX 1.9.9 的 RootFS 丢失点已在 Steam Runtime 内复现，当前测试 Guest 已备份并修正单项注册配置，动态 x86-64 探针通过。进入游戏仍需实测。接续开发应将此项作为有审核和回滚的部署变更，完整记录见开发状态。


## FX 1.9.9 RF 恢复及 GUI 启动（2026-11-14）

本轮实际证据见 [修复报告](environment/FX199_RF_REPAIR_20261114.md)。正式盘未写入；测试盘十文件有完整备份及回执。GUI 启动/EAC 引导/游戏进程窗口通过，主菜单或飞船由用户确认，单人/多人按用户选择未测。下一步完成新 UI 截图、回归和内部候选；自动更新真实安装闭环与玩法门禁未过，不发布公开 Beta。当前任务分支以 Git 实际 HEAD 为准。

最终内部 RC：1.0.0 (2026111403)，干净构建源码 `4119d65e64468afaa763cf8ffc134a34786bb83f`；DMG `/Volumes/Thunderbolt2TB/绝地潜兵脚本/HD2-App-Builds/Candidates/FX199-RC-20261114-2026111403/HD2FXNative-v1.0.0-macOS-arm64.dmg`，SHA-256 `59730d98f3a4c358ca335da481d170f57c452d075728441147aa38723c50a478`。arm64 Release、ad-hoc、资源/秘密扫描、DMG 校验/只读挂载/安装副本及卸载后实际进程启动均通过。最终完整核心检查 549 项及更新专项通过；末次仅补面板重试入口并重新 Debug/Release 编译，未声称重跑全部核心测试。终态按钮动态交互、真实更新安装/恢复和单人/多人仍待验收；不发布、不合 main。源码分支 `fix/fx199-verified-rf-20261114`，远端以实际 ref 查询为准。


## 用户授权 main 合并（2026-11-14）

用户已明确授权将 FX 修复与 UI／凭据／更新安全候选合并 main 并推送。以最新 origin/main 0eb1f3e 整合候选 7a16400；保留 main 已发布 v1.0.0 的下载入口和发布说明，旧记录中“不合 main／尚未发布”仅描述当时阶段。GitHub API 已确认现有 v1.0.0 为公开稳定版，资产与候选同一 DMG。本次不发布、替换或删除 Release、tag 或安装包。保留全部真实玩法、sudo、凭据及更新完整闭环的未验收限制，不因源码合并而升级状态。

集成冲突仅涉及双语 README/CHANGELOG；Native 代码及资源与已验证候选逐字节一致。full-audit 工作树的未提交成果未改动，其补丁和未跟踪文件另存 Backups/main-merge-20261114。main 工作树原本干净；合并通过必要检查后普通推送，实际提交/远端状态以 Git 为准。

本次 main 整合验证：Debug 构建通过；完整 run_checks.sh 及更新专项均退出 0，549 项 Swift 核心回归通过，更新服务 39／管理器 23 及归档相关检查通过；十语言、14 图来源、双语文档、diff 与暂存秘密扫描通过。整合期间保留远端后续 fa82837 的 README 排序与凭据说明；源码合并不等于新增实机验收，也不重建已发布 DMG。

## 自动更新隔离候选 · 2026-11-14

基于远端 main `cd42dca30c85d5762c5f7cad9270850dc78d4e3d`，独立分支 `feature/native-auto-update-20261114`。候选将「下载并安装」接至既有校验下载再交给 Sparkle，并使原生检测/下载时的取消入口可见；无新增翻译键。现有生产公钥、服务和分发就绪标志仍为空/关闭。v1.0.0 标签配置亦如此，因此该旧版不能安全地自动引导到新信任根，需可信手动安装一个已配置公钥的引导版本。

候选未完成：Sparkle 仍会另行下载并可能弹确认；真实隔离升级、故障注入、重启确认、安装后自动回滚、正式签名密钥和发布链路未完成。不能当作可发布的自动更新功能。不得覆盖 v1.0.0、发布 v1.0.1 或修改游戏环境。接续先设计可信引导及独立辅助程序恢复协议，再进行隔离端到端验收。具体验证和源码 SHA 以本分支 Git 记录及最终报告为准。

截图门禁因更新界面源码变化而失败；中英文真实截图尚未重拍及复核，不应视为已通过。

## 应用名称统一 · 2026-11-14

简体、繁体名称与其他语言英文名称已统一；保留内部 App 文件名、Bundle ID 和数据位置。v1.0.0 更新服务未配置，不能据更名推断自动升级可用；实际升级验收仍待完成。截图为历史构建，更新后的真实截图待采集。

首页 LED 整合：品牌 main 已包含，状态颜色组合隔离验证，中英文首页 Debug 截图已更新；其他页面截图待复核。EAC/联机未做实机验证。

未完成：LED 八种布尔组合仅验证纯逻辑优先级，未完成真实状态注入的界面颜色矩阵及运行时动态验证；FX/Steam 进程检测仅显示灰色“已检测到进程”，不能当作完整就绪。完成矩阵及审核后才可晋级 main。

## v1.0.1 更新接续 · 2026-11-14

已整合包含品牌及 LED 的 main b789642；保留既有更新签名和 ZIP 检查。候选版本 1.0.1/build 2026111404，公钥固定在 Updates.xcconfig。独立 update_signing.swift 以仓库外 0600 文件管理私钥，不访问 Keychain，不打包到 App。原 prepare_native_release.sh 为历史 Keychain/Developer ID 路线，本轮未执行，不适用于本次无 Keychain 交付。

未完成：重复下载/确认消除、独立安装和健康确认/回滚协议、真实 1.0.1→1.0.2 升级及故障矩阵。仅配置公钥不代表服务就绪，保留服务关闭。未发布 Release、未晋级 main。截图与真实安装仍需完成，草稿 PR 必须保持未合并。

本轮验证：1.0.1/2026111404 arm64 Debug 构建通过；更新服务39、管理器24、资源5、历史10、ZIP7检查通过；文件签名工具验证通过；十语言596键、双语文档15项及 App产物秘密扫描通过。真实中英文截图驱动运行成功，但更新区域滚动位置错误，截图待修复重采集。真实安装/回滚未执行，不能晋级 main。

## 独立安装助手候选 · 2026-11-14

Swift 服务保留签名清单原始字节和签名，将已经下载的 ZIP 交给单一 Helper。Helper 从当前 App 读取固定公钥，用复制到私有事务目录的归档复验 SHA-256、Ed25519 和 ZIP 结构，然后提取并校验 App 签名、版本、Bundle ID 和公钥连续性。旧 App 在 Helper 提示准备就绪后正常退出。Helper 使用同卷原子交换保留旧包，新 App 主窗口可见后写出本次启动令牌。未收到令牌或进程提前退出时恢复旧包并确认其启动。事务日志保存在安装目录旁。Sparkle 运行时的安装入口移除，历史打包和框架依赖保留。

隔离测试使用临时密钥和实际 ad-hoc 签名的 AppKit 测试包，不读取正式私钥或用户数据。Helper 若被强制终止，现场、日志及交换后的旧包会保留在 .HD2FXNative-update，后续安装会拒绝覆盖。自动接管中断事务、真实启动器单击跨版本升级和用户配置保留验收仍待完成。生产服务继续关闭。

续测 PR #4 的隔离测试版：在 1.0.1-update-test.1 设置页检查更新并单击下载安装，核对 ZIP 网络事务、同路径新版启动、安装日志和隔离偏好。

2026-11-14：隔离 GitHub 更新已实测保留真实 FX 测试路径、语言和主题。实际低空间卷、不可写安装目录及中断恢复通过。v1.0.1 构建 2026111406 使用 GitHub Releases 稳定渠道。


## 新镜像首次配置实测 · 2026-11-15

在 steamos-1.img / FX 1.9.9 上，从真实 Debug App 首次配置页点击自动配置。准备 FX、SSH 凭据复用及 Guest 身份核对通过，环境检测返回 FEX_PROTON_INTEGRATED_UNVERIFIED，界面显示具体阻塞并保持配置未完成。未进入下载或 Guest 配置写入，未启动游戏。沿用既有 Proton-JE 下载、校验及安装器；本次未实际执行该安装器。Proton 内置 FEX 的版本、Config.json SHA-256 和库哈希进入只读快照。尚无适用于该结构的经过验证的完整 FEX/RootFS 部署方案，因此不能将首次配置标记成功。十语言文案沿用前一提交，11项 FEX 探针检查、arm64 Debug 构建及双语文档检查通过。当前实际 App 屏幕验收为阻塞路径。


2026-11-15 recovery continuation: use fix/first-run-ssh-access in /private/tmp/hd2-fex-merge.9K0x03. See docs/testing/NATIVE_FIRST_RUN_ACCEPTANCE.md for current live failure and exact hashes. Next work must identify the boot-time FEX overwrite owner and design identity-bound durable integration; never approve the known incompatible stock FEX or publish unreviewed RF binaries. Runtime is retained, Proton installed, game not launched; no main merge/release. Screenshot-source gate is pending; targeted checks and arm64 Debug pass.

## 首次配置实施方案 · 2026-11-16

下一版采用混合部署：已审核的 RF FEX 优先内置 App，受信 HTTPS 下载为备用；配置模板随 App 交付。Proton-JE 和 SteamLinuxRuntime_4 复用现有固定版本自动下载，保留系统的 SteamLinuxRuntime_4-arm64。普通用户无需提供 RF 文件。当前 Debug 本地样本入口仍是隔离测试工具，公开构建需先核实全部组件来源、构建版本、许可证和再分发许可。见 [组件清单](environment/ENVIRONMENT_COMPONENT_MANIFEST.md)。

1. 从 App 资源目录读取批准清单及 RF 包，校验文件大小和 SHA-256。备用下载采用相同身份和完整性约束。包损坏或来源不符时停止。
2. 通过已验证目标和 Guest 身份的 SSH/SFTP 上传到暂存目录。复用 FEX 部署事务，在持久化 /home 下的 App 独立目录进行原子切换，保留回滚回执及先前目录。
3. 验证实际加载的 FEX 路径和哈希。分别核对 emulator 注册、provider 生成的配置及实际观测到的探针变量，保留有效配置，不强制设定 `FEX_ROOTFS=/`。
4. 正常重启两次后重连，复验文件哈希、加载路径、Steam 兼容工具及参数。重复执行时跳过已验证组件。失败时根据回执恢复，发现漂移则停止覆盖。
5. 用全新测试镜像完成真实首次安装验收，分别记录配置完成和游戏启动结果。历史成功镜像只用于读取证据。[实测结果和待验证项目](testing/NATIVE_FIRST_RUN_ACCEPTANCE.md)

## 真实用户 FEX_MISSING 修复候选 · 2026-11-22

分支 `fix/first-run-ssh-access` 的起点及原远端提交均为 `c32ce24b9cfd90d197b21cc9cfda45ce3948c0a8`；开发在独立工作树进行，未覆盖其他工作树。截图能确认 FX 与 SSH 成功、环境检查以内部码 `FEX_MISSING` 失败，不能单凭截图认定 ID、权限或资源缺失。

源码追踪确认旧流程在检测到缺失后直接抛错，未进入既有安装事务；同时游戏检测只看当前 SSH 用户默认 Steam 目录。候选将缺失和可修复损坏状态自动送入修复阶段，分别记录组件不存在、二进制缺失、权限、可执行位、架构、完整性、注册、RootFS 与实际运行失败。Steam 游戏目录从 `libraryfolders.vdf` 发现，当前账户由 `loginusers.vdf` 的唯一 MostRecent SteamID64 推导账户 ID；没有个人 SteamID 白名单或固定生产 UID/GID。SSH HOME 和账户仍以已认证会话及 `id -un` 验证为准。

当前公开 RF Bundle 仍为空，JSON 清单继续标记 `BLOCKED_PUBLIC_RF_DISTRIBUTION`，网络备用源为 `UNVERIFIED`。自动修复不会把新的固定源码构建输出误认作历史批准哈希；没有准确匹配的已审核候选时返回 `ARTIFACT_UNAVAILABLE / RF_BUNDLE_PAYLOAD_UNAVAILABLE`，保留重试和脱敏诊断。P1 及后续真实恢复、App 首配、两次重启和游戏验收因此仍受阻，不得破坏现有成功盘或冒充完成。详见[故障分析](environment/FIRST_RUN_FX_RUNTIME_FAILURE_20261122.md)。

受控 Debug 内置、导入命令与验收状态见[专项报告](testing/RF_FEX_BUNDLED_DEPLOYMENT_ACCEPTANCE.md)。


## 启动诊断接续（2026-11-25）

`dev/core` 基于正式 1.0.5（`b19f23e`）。启动工作流以同一 UUID 关联阶段和失败，Guest 返回 Steam 派发命令退出码。该退出码只描述命令，游戏窗口、游戏进程退出原因和五分钟运行仍需真实 Guest 证据。本机已备份并尝试安装正式 1.0.5，尚未获得关联的实际点击与 Guest 日志。公开 RF 制品和干净镜像验收仍待完成。

正式 1.0.5 本机打开失败。macOS 27.2.1 崩溃报告为 DYLD，Sparkle 已嵌入但 App 和框架均为 ad-hoc hardened runtime 签名且都没有 Team ID。本机回退至备份的 1.0.4。候选发布门禁拒绝 hardened runtime 与 Sparkle 签名队伍不匹配的制品。正式重打包及正常打开验收仍待完成。

本机候选 `ba5ee53` 的 arm64 Release 构建、ad-hoc 签名、Bundle 门禁和更新 ZIP 打包通过。它未替换正式安装。2026-11-25 23:49:44（上海）从候选总览实际发起任务 `61E16B21-AFB4-42B4-8439-CD020094268C`，进入 SteamOS 检测及配置复验，23:50:45 以 `USER_ACTION_REQUIRED`（`component=launch`）退出。没有进入 Steam 派发阶段。该码表明 LaunchOptions 未取得可验证值，未定位到更底层的在线 Steam API 或文件读取失败原因。历史 12 秒退出仍需 Guest 日志。测试完成前不应以该候选替代正式发行。
