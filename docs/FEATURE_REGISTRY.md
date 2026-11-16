# 功能与开发状态索引

核对日期：2026-11-16（Asia/Shanghai）；主线基线 `04f9fb40c7832c50b107210fd3a5a7f70fadd3b6`。这是可供后续 Codex 接续的索引，不替代实际代码、当前 Git 状态或具体验收记录。检查顺序：开发状态与交接 → 本索引 → 当前代码和相关分支/PR → 判断是否需要开发。完成开发、修复、测试或合并时同步更新本表和交接；勿将隔离测试、文件存在或历史成功当作当前实机通过。

后续固定分支：`dev/environment` 管理 FX/SteamOS/FEX/Proton/Runtime/首次配置，`dev/ui` 管理界面、设计与本地化，`dev/core` 管理启动、SSH、凭据、日志、更新及共享规范；`main` 为稳定发布，`legacy-script` 保留原终端脚本。开发前先检查相应固定分支及其工作树，并核对下表历史分支；存在未合并的独有成果不代表可以覆盖或直接整枝合入。每个固定开发分支最多一个常驻 worktree；新临时分支须用户事先授权。已完成工作应按功能更新本表和交接，记录文件、分支/提交、main 归属、测试范围/结果/日期及剩余事项。

状态可同时表达归属和验证：**已整合 main** 表示代码存在于基线；**已验证**必须限定测试范围；**已实现未验证**指相应真实路径未验收；**开发中**和**已完成但未合并 main**表示分支状态；**未实现**或**已废弃**不代表历史记录应删除。下表所有条目的最后核对时间均为 2026-11-16；提交是对应代码或证据的可追溯历史点，不声称该提交单独包含整个功能。后续通过 `git log -- <文件>`、`git merge-base --is-ancestor` 和远端 API 刷新，不在提交内循环写入自己的 SHA。

## 主线功能

| 功能及位置 | 状态、所属提交和 main 归属 | 测试/证据及剩余工作 |
| --- | --- | --- |
| 固定分支、工作树和共享进度：`AGENTS.md`、`docs/NATIVE_DEVELOPMENT.md`、`.github/workflows/native-release-check.yml` | 已整合 main；`dev/core` 的 PR #18/#19 | 2026-11-16 文档检查 15/15、相对链接、diff、敏感信息模式扫描及工作流 YAML 语法通过；远端三个固定开发分支与 main 同步。未运行 App 回归或实际触发工作流；历史工作树逐步复核，未经授权不创建临时分支。 |
| 导航、仪表盘、状态灯：`native-app/Models/Navigation.swift`、`native-app/Views/DashboardView.swift` | 已整合 main；`b7e8a20`，状态灯历史 `b789642` | 隔离状态矩阵与截图有历史记录；进程检测不等于 EAC 或联机成功，实际状态矩阵仍需验收。 |
| 战术布局、美术及语言：`native-app/Views/FirstRunSetupView.swift`、`native-app/Resources/native-locales.json`、`docs/images/manifest.json` | 已整合 main；`6a83b6c`、`da3e149` | 2026-11-16 十语言静态检查、README 截图来源检查通过；动态文案和各语言自然度需人工复核。 |
| FX 发现、选择与身份：`native-app/Core/FXDiscoveryService.swift`、`native-app/Services/FXSelectionManager.swift` | 已整合 main；`3ad6693` 等 | 2026-11-16 核心/身份隔离检查通过；实际 FX/Guest 身份、版本差异及新环境仍需独立验证。 |
| SSH 与 Guest 身份：`native-app/Core/SSHTransport.swift`、`native-app/Core/GuestService.swift` | 已整合 main；`ec71958`、`37852a5` | 2026-11-16 SSH/Guest 隔离回归通过；真实身份漂移、认证及 sudo 不由 fixtures 证明。 |
| SSH/sudo 凭据及可选加密保存：`native-app/Services/SessionCredentialManager.swift`、`native-app/Services/LocalCredentialStore.swift` | 已整合 main；`f855c05`、`37852a5` | 2026-11-16 凭据和持久化隔离测试通过；真实重启后恢复/拒绝/遗忘与目标变化需验收。旧文档“main 仅内存”是历史阶段，不是当前状态。 |
| 首次配置向导、部署计划与回执：`native-app/Views/FirstRunSetupView.swift`、`native-app/Core/EnvironmentDeployment.swift`、`native-app/Core/EnvironmentAdapters.swift` | 已整合 main；`6a83b6c`、`37852a5`；真实全新镜像路径已实现未验证 | 2026-11-16 部署隔离回归 153 项通过；不证明新镜像端到端部署。新 RF 方案仍在独立分支，见下表。 |
| FEX/Proton 组件探测、候选及恢复：`native-app/Core/ComponentDeploymentAdapters.swift`、`docs/environment/FEX_CANDIDATE_PIPELINE.md` | 已整合 main；`9eaa9d2` 等；实际新环境安装未验证 | 2026-11-16 FEX/部署 fixtures 通过；保持身份、完整性和恢复门槛。历史 RF、Proton-JE 和 Runtime 证据不等于完整发行方案可用。 |
| 配置和性能管理：`native-app/Core/ConfigurationService.swift`、`native-app/Core/PerformanceConfigurationService.swift`、`native-app/Views/GamePerformanceView.swift` | 已整合 main；`126154f` 等 | 2026-11-16 相关隔离回归通过；真实性能配置效果和恢复待实机验收。旧版宽泛 profile 应用已废弃，当前代码禁止该路径。 |
| SteamOS 网络与诊断：`native-app/Core/SteamOSNetworkService.swift`、`native-app/Core/NetworkDiagnosticsService.swift` | 已整合 main；`104beaa` | 2026-11-16 网络隔离回归通过；IPv6 操作需显式用户操作；不能据只读诊断推断游戏匹配或多人成功。 |
| 启动、等待与日志：`native-app/Core/NativeCoreService.swift`、`native-app/Core/LaunchService.swift`、`native-app/Views/LogsView.swift` | 已整合 main；`37852a5`、`ec71958` | 2026-11-16 核心/启动 fixtures 通过；真实游戏、EAC、单人、多人及本版完整启动未验证。 |
| 更新检测、签名下载与单操作界面：`native-app/Services/UpdateReleaseService.swift`、`native-app/Services/AppUpdateManager.swift`、`native-app/Views/SoftwareUpdateView.swift` | 已整合 main；`f573a09`、`da3e149`；生产升级仍未验收 | 2026-11-16 更新服务 44、管理器 14 项隔离检查通过；实际服务检测并下载验签 v1.0.3。主线代码与开放 PR #8 的四个更新核心文件逐字一致；PR 仍开放，勿重复合并。 |
| 更新安装、重启确认与失败恢复：`native-app/UpdateHelper/UpdateInstaller.swift`、`native-app/UpdateHelper/UpdateZIPPreflight.swift` | 已整合 main；`90f6931` 等；真实版本间端到端升级已实现未验证 | 2026-11-16 临时密钥/隔离 AppKit 测试覆盖安装、启动确认、失败回滚和中断恢复；不证明发布版 App 实际升级。v1.0.1 可能需 DMG 手动升级。正式发布默认需实际安装、升级及失败恢复验收；明确授权的非安全验收例外须逐项记为未验证。 |
| 正式 Release 与签名清单：`native-app/Config/Updates.xcconfig`、`native-app/script/package_update_zip.sh`、`.github/workflows/native-release-check.yml` | 已整合 main；v1.0.4 已发布；PR #14 已合并，标签指向 `6987fae` | 现有 ad-hoc 签名、固定 Ed25519 公钥和正式发布资源已配置；不等于 Apple 公证或生产升级通过。旧记录“无正式包/生产服务关闭”是历史阶段。发布门禁见 [NATIVE_UPDATES](NATIVE_UPDATES.md)。 |
| FX/SteamOS 安全停止或重启后端 | 未实现或未证明安全，保留不可用状态；不可用强制终止替代 | 需要可靠生命周期后端和独立实机验收；本轮不开发。 |
| Python Bridge 运行时 | 已废弃；`legacy-script` 为历史兼容快照 | 当前 App 使用 Swift Native Core；不得恢复或随意推进 CoreSnapshot。 |

## 保留的开发与发布记录

| 功能及位置 | 状态、分支/提交和 main 归属 | 证据及剩余工作 |
| --- | --- | --- |
| RF 优先随 App 交付、已校验网络备用及模板：`docs/environment/ENVIRONMENT_COMPONENT_MANIFEST.md`、`native-app/Resources/deployment-components-v1.json` | 开发中；`origin/fix/first-run-ssh-access` `c32ce24`；**未合入 main** | 分支验收报告记录既有镜像 100%、两次正常重启及 18 项哈希一致；RF 实际打包、全新镜像首次安装和再分发许可待验证。不得将部署规范当作实现完成；本轮不开发首次配置。 |
| 首次配置 SSH、RootFS 与运行时分支：`native-app/Core/`、`docs/testing/NATIVE_FIRST_RUN_ACCEPTANCE.md` | 开发中；`origin/fix/first-run-ssh-access` `d4652a6` 等独有提交；未整体合入 main | 有分支测试及既有镜像记录；分支与当前 main 的逐功能整合及全新镜像验收仍待专门任务，保留原分支。 |
| 更新器单操作候选：`native-app/Services/AppUpdateManager.swift`、`native-app/Views/SoftwareUpdateView.swift` | 已有等效主线实现；`origin/fix/simplify-update-button` `8b3ac32`，PR #8 开放 | 主要四个更新核心文件与 main 字节一致；PR 存在，保留并另行核对剩余文档/测试，不能以提交图未包含判断功能未实现。 |
| 历史完整审计候选：`docs/HD2_NATIVE_FULL_AUDIT_20261106.md`、`native-app/Core/` | 未完成的 WIP；`feature/full-native-audit-20261106` `a96acac`；未合入 main | 旧候选混合 UI、凭据、部署和启动修改，部分已有较新主线实现；保留工作树与提交，逐项复核，禁止整树覆盖。 |
| FX 1.9.12 历史环境证据：`docs/environment/FEX_SUCCESS_ENVIRONMENT_REPORT_FX1912_20261115.md`、`docs/environment/FEX_ENVIRONMENT_COMPARISON_FX199_VS_FX1912.md` | 已整合 main；PR #13，基线 `04f9fb4`；原 `docs/fx1912-success-environment-20261115` 工作树保留 | 2026-11-16 原文对照、相对链接和敏感信息模式扫描通过；观察和历史会话不证明当前游戏/最小部署方案。 |
| 1.0.4 发布：`native-app/HD2FXNative.xcodeproj/project.pbxproj`、双语 CHANGELOG | 已整合 main；PR #14，v1.0.4 标签 `6987fae`；用户明确决定不等待额外验收而发布 | 2026-11-16 发布包 arm64/ad-hoc、ZIP 策略、DMG 校验、签名清单及 SHA-256 通过；真实跨版本应用内升级、升级后自动重启及生产环境失败恢复均未验证。旧候选 `2b31065` 与正式包来源不同。 |

## 审计及复用证据

2026-11-16 已审计 70 个分支名称（含当时的整合分支），保护并清理 25 条远端已合入分支；包含全部引用的六个 bundle 已验证，原始 refs、SHA-256 和分类在本机 `绝地潜兵脚本/Backups/branch-audit-20261116/`。备份是本机证据，不是远端归档；未证明等效、开放 PR、被工作树使用及首次配置开发分支继续保留。实际状态以 GitHub 和 `git worktree list` 为准。

2026-11-16 固定分支建立时，对保留的远端历史分支按主要后续归属分类；跨领域分支需要分别审核，分类不是迁移完成或可删除证明：

- **环境 → `dev/environment`**：`docs/fx1912-success-environment-20261115`、`feature/native-recovery-20261112`、`fix/first-run-ssh-access`、`fix/fx199-fex-readiness-20261114`。首次配置分支含独有开发成果，继续保留；不得因新分支建立而覆盖或自动合并。
- **界面 → `dev/ui`**：`feature/localized-app-brand-20261114`、`integration/dashboard-led-brand-20261114`、`ui/motr7-artwork-20261114`。已有等效成果需对照当前代码，正在使用的工作树保留。
- **核心/共享规范 → `dev/core`**：`backup/stable-publish-20261114`、`chore/swift-incremental-checks-20261114`、`docs/feature-registry-20261116`、`docs/github-release-policy-20261114`、`docs/v1-release-preparation-20261113`、`docs/v104-published-20261116`、`docs/v104-release-20261116`、`feature/full-swift-native-migration`、`feature/macos-native-app`、`feature/native-auto-update-20261114`、`fix/live-logging-launch-20261114`、`fix/native-launch-resources-20261103`、`fix/simplify-update-button`、`integration/branch-audit-20261116`、`release/candidate-1.0.4-20261116`。PR #8 仍开放，工作树和备份依赖保留。
- **跨环境、界面和核心**：`feature/full-native-audit-20261106`、`release/v1.0.0-integration`。按实际文件拆分归属到上述固定分支；旧候选未完成或含历史实现，保留并逐项复核。

本机独有分支和各独立 Git 仓库的 refs 见上述本地审计清单；它们没有因远端分类自动合并或删除。固定分支初始基于当时 main；后续开发前重新 fetch 和核对各自状态。

复用测试基线：2026-11-16、`ba7e495`（与 main `04f9fb4` 的文件树相同，仅提交历史不同），独立 worktree 执行 arm64 Debug、`native-app/script/run_checks.sh`、`run_update_checks.sh`、十语言和 `script/check_docs.py`（15/15）通过。具体输出位于该 worktree 的 `native-app/evidence/`；该目录为本机证据，不承诺存在于其他机器。隔离安装助手及实际 v1.0.3 检测/下载证据属于 2026-11-16 本机测试；均不证明新版本生产升级。后续代码、依赖或环境变化时按受影响范围重验。
