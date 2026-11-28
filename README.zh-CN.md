<div align="center">

v1.1.1 改善 SteamOS 密码设置，并优化 FX Steam Launcher 1.9.15 的 DirectX 11 和 DirectX 12 切换。安装和升级后，DirectX 12 仍为默认模式。
  <img src="docs/assets/app-icon.png" width="128" alt="绝地潜兵 2 FX 启动器 icon">
  <h1>绝地潜兵 2 FX 启动器</h1>
  <p>HELLDIVERS 2 FX Launcher · Apple Silicon macOS</p>
</div>

[简体中文](README.zh-CN.md) | [English](README.md)

<!-- stable-download:start -->
### [🟨 ⬇️ 下载 绝地潜兵 2 FX 启动器 最新正式版](https://github.com/LSJOP/helldivers2-fx-launcher/releases/latest/download/HD2FXNative-v1.1.1-macOS-arm64.dmg)

**🟨 Stable Release · v1.1.1** · **macOS · Apple Silicon / arm64**

**[⬇️ 立即下载 DMG](https://github.com/LSJOP/helldivers2-fx-launcher/releases/latest/download/HD2FXNative-v1.1.1-macOS-arm64.dmg)** · [查看所有版本](https://github.com/LSJOP/helldivers2-fx-launcher/releases)
<!-- stable-download:end -->

## 简体中文

绝地潜兵 2 FX 启动器是面向 Apple Silicon Mac 的第三方社区启动与管理工具，使用 SwiftUI 和原生核心，帮助用户检查 FX 环境、配置运行环境和管理游戏性能设置。

DX12 沿用原启动流程。参考记录覆盖 FX 1.9.12 的历史 Vulkan 环境，以及 FX 1.9.15 已通过实测的同盘 DX12 恢复。[FX 1.9.12 历史记录](docs/environment/FEX_SUCCESS_ENVIRONMENT_REPORT_FX1912_20261115.md) · [图形环境基准](docs/environment/HD2_SUCCESSFUL_ENVIRONMENT_BASELINE.md)

### DirectX 11 高性能模式（实验性）

在游戏性能配置页启用 DirectX 11（DXMT），然后从总览启动。App 自动配置独立的 Proton-JE 工具和 Wine 前缀。FX 内置 DXMT 通过 Metal 渲染，并保留游戏声音。两种模式共用已有游戏、Steam Runtime 和虚拟磁盘，无需重新下载游戏或复制磁盘。退出游戏后再关闭 DX11，或点击「恢复 DX12」以恢复原配置。

DX11 已在 FX 1.9.15 实机验证，FX 1.9.12 的 DX11 和多人联机尚未完成本轮验收。DXMT 可能扩大 Guest 对 Mac 的访问范围，需主动确认。当前配置关闭 TAA 和麦克风输入。游戏可能提示驱动版本，需要手动选择继续。[图形环境和恢复方法](docs/environment/HD2_SUCCESSFUL_ENVIRONMENT_BASELINE.md#dx11--dxmt-已验证成功环境--2026-11-28)

Apple M4 Pro、24 GB 统一内存，1280×800 舰桥同场景短测的游戏帧率中位数为 **DX12 42 FPS**、**DX11 + DXMT 98 FPS**，约 **2.33 倍**。两组音频模式和宿主内存压力存在差异，结果仅覆盖本次场景和设备。[测试条件](docs/environment/HD2_SUCCESSFUL_ENVIRONMENT_BASELINE.md#验收索引和限界)

### 软件截图

DX11 截图复用版本号为 v1.0.8 的真实验收候选。其余截图来自早期隔离 Debug 构建。[截图记录](docs/images/README.md)

总览 V003 集中提供基于路径的 FX 实例选择与控制，运行环境保留高级诊断。滚动条隐藏，页面仍可滚动。四张状态卡显示 FX、Steam、EAC 和联机，Guest 证据在运行环境查看。

| 总览 | 首次运行环境配置 |
| --- | --- |
| ![总览](docs/images/zh-CN/dashboard.png) | ![首次运行环境配置](docs/images/zh-CN/first-run-setup.png) |
| 运行环境 | 日志 |
| ![运行环境](docs/images/zh-CN/environment.png) | ![日志](docs/images/zh-CN/logs.png) |
| 游戏性能配置 | 设置 |
| ![游戏性能配置](docs/images/zh-CN/performance.png) | ![设置](docs/images/zh-CN/settings.png) |
| 总览的 DX11 模式 | DXMT 图形设置 |
| ![总览的 DX11 模式](docs/images/zh-CN/dxmt-dashboard.png) | ![DXMT 图形设置](docs/images/zh-CN/dxmt-performance.png) |

[DXMT 首次启用风险提示](docs/images/zh-CN/dxmt-consent.png)

### 主要功能

配置与启动流程美术作品由 **MOTR7** 创作，经作者授权使用（由用户提供）；首页主视觉和统一页面横幅保持不变。开发候选将首次配置置于侧边栏第一位（⌘1），默认页面仍为总览（⌘2）。

**界面更新：**运行环境和日志页使用统一的内容区快照刷新；FX 详情复用检测结果，避免界面重绘时反复计算哈希。

日志页使用系统本地时间，实时显示有容量限制的任务事件，支持自动滚动和导出脱敏的原始 ISO 8601 时间戳。启动命令成功、游戏进程、窗口和实际进入游戏分别记录；窗口及游戏内状态不会自动推断。

- 从总览发起带保护检查的 HELLDIVERS 2 启动流程。总览提供实例选择及受支持的 FX 启动操作。
- 首次运行环境配置检查 Guest 身份、运行能力和组件完整性。经确认后可安装固定版本的 Proton-JE、选择已验证的 Steam 兼容工具，并合并启动参数以保留自定义参数。检测为只读，部署与恢复各有检查条件。
- 在设置中统一输入 SteamOS 密码。SSH 与 sudo 各自认证，已保存的凭据按 FX 实例、磁盘与连接端点限定范围并加密。可在日志页复制脱敏诊断报告。
- Swift App 提供六个原生页面、日志、限定范围的性能设置和十种界面语言。SteamOS 内的可选安装步骤需要 Python 3。
- 在「设置 → 软件更新」中检查稳定版。v1.0.1 无法安装已发布的 v1.0.2 更新 ZIP，请使用 DMG 安装 v1.0.2。

### 安装说明

<!-- stable-install:start -->
当前 App：`1.1.1`（构建 `2026112906`），适用于 macOS 14+ Apple Silicon arm64。采用 ad-hoc 签名，无 Apple Developer ID 签名，未经 Apple 公证。Gatekeeper 可能拦截下载副本；打开前核对 [SHA-256 文件](https://github.com/LSJOP/helldivers2-fx-launcher/releases/latest/download/SHA256SUMS.txt)。若被拦截，对已核验 App 使用「隐私与安全性 → 仍要打开」。
<!-- stable-install:end -->

1. 从正式 Release 下载 macOS arm64 DMG。
2. 运行 `shasum -a 256 <下载的 DMG>`，与发布说明中的 SHA-256 比对。匹配后打开 DMG。
3. 将 App 拖入「应用程序」。
4. 打开 App。
5. 在总览中选择已安装的 FX Steam Launcher，按首次运行向导操作。SteamOS 内须安装 Steam 和 HELLDIVERS 2（AppID 553850），使用拥有游戏的账号，并确保 Guest 可通过 SSH 访问。在 App 内输入所需凭据并审核拟执行的变更。
6. 在总览点击「启动 HELLDIVERS 2」。

从源码构建请参阅[开发指南](docs/NATIVE_DEVELOPMENT.md)。

### 已知问题

- FX 和 SteamOS 兼容性取决于所选构建与运行环境。DX11 本轮从已安装游戏验证至舰桥，其他 Proton 版本、实体麦克风及游戏内语音不在本轮验收范围内。
- 部分 Guest 可能遇到 Steam 登录或驱动提示。App 保留原 DX12 环境供恢复。
- v1.0.1 会在 ZIP 安全检查时拒绝已发布的 v1.0.2 更新包，请使用 DMG 升级。App 使用 ad-hoc 签名且未经公证，可能受到 Gatekeeper 拦截。
- [验收报告](docs/acceptance/RELEASE_READINESS_REPORT.md) · [已知问题详情](docs/acceptance/KNOWN_ISSUES.md) · [首次运行验收](docs/testing/NATIVE_FIRST_RUN_ACCEPTANCE.md) · [更新机制](docs/NATIVE_UPDATES.md) · [性能设置限制](docs/GAME_PERFORMANCE.md)

### v1.0.7 组件审核

v1.0.7 审核记录了 RF FEX 和 Proton-JE 的许可、来源及实机验收。RF 包使用项目自有 wrapper 与 FEX MIT 声明。Proton-JE 归档绑定上游标签、二进制校验值和 62 个递归源码子模块。[RF 审核](docs/audits/RF_FEX_Redistribution_Audit.md) · [Proton-JE 审核](docs/audits/Proton_JE_Redistribution_Audit.md) · [v1.0.7 就绪报告](docs/acceptance/v1.0.7_Release_Readiness.md)

### 更新日志

<!-- stable-version:start -->
[v1.1.1 — 2026-11-29](https://github.com/LSJOP/helldivers2-fx-launcher/releases/latest) · 正式稳定版，构建 `2026112906`。见[发布说明](CHANGELOG.zh-CN.md)。
<!-- stable-version:end -->

当前功能状态、验证范围和未合并成果见[功能索引](docs/FEATURE_REGISTRY.md)、[更新日志](CHANGELOG.zh-CN.md)及[原版启动器历史](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script)。

### 免责声明

本项目由社区开发，与 HELLDIVERS 2 官方无关联，相关名称及商标属于各自权利人。项目尚未选定全项目源码许可证；第三方组件与素材说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

### 文档

使用与开发指南、架构说明和历史报告见[文档索引](docs/README.md)。

接续开发请读取[当前状态](docs/DEVELOPMENT_STATUS.md)和[交接文档](docs/NATIVE_APP_DEVELOPMENT_HANDOFF.md)，以 main 源码与 AGENTS.md 为准，未合并候选及实机验收单独记录。



原生更新中断后，下次打开 App 可恢复事务。

FX 1.9.9 环境实测记录见[运行环境基线报告](docs/environment/FEX_BASELINE_REPORT_20261115.md)。

首次配置区分 Proton 内置 FX 运行环境与独立组件缺失。检测记录 Proton 版本、配置摘要和库文件哈希，在获得已批准的方案前将兼容性标记为未验证。

v1.0.5 提供组件更新引擎，并为旧正式版保留小体积 ZIP。后续兼容版本可复用校验匹配的内置组件，并保留已验证的全量 ZIP 备用。三个历史运行组件仍限受控测试。若应用内更新失败，请核验并挂载完整 DMG，退出启动器后替换现有 App。已保存设置和 SteamOS 镜像继续使用。见[组件更新验收](docs/testing/COMPONENT_UPDATES_ACCEPTANCE.md)。

环境配置分支优先使用 App 内置的 FX 运行组件和 Proton-JE，以获批的固定版本和哈希校验下载为备用。Steam Linux Runtime 4.0 由 Guest 内的 Steam 管理。缺失时需要 Steam 联网，已验证兼容的安装会复用。FX 和 Proton-JE 的公开分发审批与真实部署验收仍待完成。见[部署验收报告](docs/testing/RF_FEX_BUNDLED_DEPLOYMENT_ACCEPTANCE.md)。

早期恢复工作已接入固定版本 Runtime 的隔离 Debug 安装（已验证本地归档或 Valve HTTPS、SHA-256、SFTP、保留 ARM64 Runtime、事务恢复）。公开版一键配置仍受 RF 二进制来源／再分发许可审核阻塞；Debug 回放需明确传入测试镜像与资源目录。见[首次配置验收](docs/testing/NATIVE_FIRST_RUN_ACCEPTANCE.md)。

持久部署候选：实测确认 Steam 在重启后更新自身运行组件 depot。恢复分支改为 App 管理目录部署 RF，并验证真实 Runtime 容器中的 RootFS。主窗口启动／重新打开及当前中英文空闲界面截图已修复；最终重复配置、跨重启验收及完整 RF 合法分发仍待完成。
