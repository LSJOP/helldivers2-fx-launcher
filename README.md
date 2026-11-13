<div align="center">
  <img src="docs/assets/app-icon.png" width="128" alt="HD2FXNative icon">
  <h1>HD2FXNative</h1>
  <p>HELLDIVERS 2 FX Launcher · Apple Silicon macOS</p>
</div>

[简体中文](#zh-cn) | [English](#english)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-333333?style=flat-square)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-333333?style=flat-square)
![Status](https://img.shields.io/badge/STATUS-DEVELOPMENT%20PREVIEW-d9aa36?style=flat-square)
![Target](https://img.shields.io/badge/TARGET-v1.0.0-d9aa36?style=flat-square)

<a id="zh-cn"></a>

## 简体中文

HD2FXNative 是面向 Apple Silicon Mac 的第三方社区启动与管理工具，使用 SwiftUI 和原生核心，帮助用户检查 FX 环境、配置运行环境和管理游戏性能设置。它不是 HELLDIVERS 2 官方软件，也不保证游戏兼容性。

**项目状态：开发预览。目标版本 v1.0.0 尚未发布。** 最终源码、截图、安装包与验收仍在准备中；游戏运行、EAC 和多人联机须分别验证。

### 下载与安装

当前没有已发布的 DMG。[查看 GitHub Releases](https://github.com/LSJOP/helldivers2-fx-launcher/releases)。发布后应从该页面下载对应 arm64 安装包，核对 SHA-256，打开映像并将 App 拖入“应用程序”。签名、公证状态和具体安装提示以实际发布说明为准。源码预览需要 Apple Silicon、macOS 14 或更新版本及完整 Xcode；参见[开发指南](docs/NATIVE_DEVELOPMENT.md)。

### 软件截图

以下是不同历史 Debug 构建的真实窗口截图，**并非 v1.0.0 最终截图**。最终版本截图待构建后重新采集、检查并替换；各图片来源见[截图记录](docs/images/README.md)。

| 总览 | 首次运行环境配置 |
| --- | --- |
| ![总览](docs/images/zh-CN/dashboard.png) | ![首次运行环境配置](docs/images/zh-CN/first-run-setup.png) |
| 运行环境 | FX 管理 |
| ![运行环境](docs/images/zh-CN/environment.png) | ![FX 管理](docs/images/zh-CN/fx-manager.png) |
| 游戏性能配置 | 设置 |
| ![游戏性能配置](docs/images/zh-CN/performance.png) | ![设置](docs/images/zh-CN/settings.png) |
| 日志 | |
| ![日志](docs/images/zh-CN/logs.png) | |

### 主要功能

- 七页原生界面：总览、首次运行环境配置、运行环境、FX 管理、游戏性能配置、日志与设置。
- 检测 FX 与运行环境；在明确确认和保护条件下提供配置、备份及恢复操作。
- 提供启动入口、SSH／sudo 授权、日志诊断和性能设置；具体行为以最终发布源码及验收结果为准。
- 原生 Mac App 使用 Swift 核心；可选的 SteamOS 内安装步骤可能需要 Python 3。

### 首次使用与启动

1. 安装并打开 App，在 FX 管理中选择可用的 FX Steam Launcher。
2. 在首次运行环境配置中检查目标及组件；在 App 的安全输入框中提供所需凭据。审阅每项具体变更和确认提示。
3. 在总览中启动 HELLDIVERS 2，按界面反馈处理错误；使用日志排查问题。检测到进程不代表已进入游戏。

### 已验证范围与限制

历史测试曾在特定环境观察到游戏主菜单；这不代表最终 v1.0.0 安装包已通过相同测试。全新环境部署、单人任务、EAC 和多人联机均需针对最终版本分别验收。实验性 FEX 候选构建曾因哈希审核不匹配而阻止部署；安装与恢复仍待实测。自动更新分发所需服务尚未完成配置。具体证据见[功能迁移记录](docs/FUNCTION_MIGRATION.md)和[更新机制](docs/NATIVE_UPDATES.md)。

### 常见问题

- **为什么某些操作不可用？** 目标身份、组件完整性、配置状态或用户确认未满足时，操作会保持受限；请阅读界面提示和日志。
- **可以从游戏进程推断联机可用吗？** 不可以；主菜单、单人任务、EAC 和多人联机是独立验收项目。

### 更新日志与原版脚本

目标版本的变更仍在整理，见[更新日志](CHANGELOG.zh-CN.md)。原版 Python 脚本及历史保留在 [legacy-script 分支](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script)，项目保留固定的 CoreSnapshot；原脚本与原生 App 的行为和要求不同。[原项目介绍与历史文档](https://github.com/LSJOP/helldivers2-fx-launcher/blob/957c8562337fd6715a03ee123e69d29d3950907e/README.zh-CN.md)。

### 免责声明

本项目由社区开发，与 HELLDIVERS 2 官方无关联，相关名称及商标属于各自权利人。项目尚未选定全项目源码许可证；第三方组件与素材说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

<a id="english"></a>

## English

HD2FXNative is an unofficial community launcher and management tool for Apple Silicon Macs. Built with SwiftUI and a native core, it helps users inspect FX, configure the runtime environment and manage game performance settings. It is not official HELLDIVERS 2 software and does not guarantee game compatibility.

**Status: development preview. Target v1.0.0 has not been released.** Final source, screenshots, installer and acceptance are still being prepared; gameplay, EAC and multiplayer require separate validation.

### Download and installation

There is no published DMG yet. [View GitHub Releases](https://github.com/LSJOP/helldivers2-fx-launcher/releases). Once published, download the arm64 installer there, verify its SHA-256, open the image and drag the App to Applications. Refer to the actual release notes for signing, notarization and installation guidance. A source preview requires Apple Silicon, macOS 14 or later and full Xcode; see the [development guide](docs/NATIVE_DEVELOPMENT.md).

### Screenshots

These are real windows from different historical Debug builds, **not final v1.0.0 screenshots**. Final captures must be taken, reviewed and replaced after the final build; see [capture provenance](docs/images/README.md).

| Dashboard | First-Run Setup |
| --- | --- |
| ![Dashboard](docs/images/en/dashboard.png) | ![First-Run Setup](docs/images/en/first-run-setup.png) |
| Environment | FX Manager |
| ![Environment](docs/images/en/environment.png) | ![FX Manager](docs/images/en/fx-manager.png) |
| Game Performance | Settings |
| ![Game Performance](docs/images/en/performance.png) | ![Settings](docs/images/en/settings.png) |
| Logs | |
| ![Logs](docs/images/en/logs.png) | |

### Features

- Seven native pages: Dashboard, First-Run Setup, Environment, FX Manager, Game Performance, Logs and Settings.
- Inspect FX and runtime components; offer configuration, backup and recovery with explicit confirmation and safeguards.
- Provide launch, SSH/sudo authorization, diagnostics and performance settings; exact behavior depends on final source and acceptance.
- The Mac App uses a Swift core; optional installation steps inside SteamOS may require Python 3.

### First run and launch

1. Install and open the App, then select an available FX Steam Launcher in FX Manager.
2. Inspect the target and components in First-Run Setup; enter required credentials in the App's secure fields. Review each exact change and confirmation.
3. Start HELLDIVERS 2 from Dashboard and follow the reported results; use Logs for troubleshooting. A detected process does not establish that the game was reached.

### Validation and limitations

A historical test reached the game menu in a specific environment; this does not establish the same result for the final v1.0.0 installer. Fresh-environment deployment, a single-player mission, EAC and multiplayer require separate acceptance on the final version. An experimental FEX candidate build was blocked from deployment by a hash review mismatch; installation and recovery still need live validation. Automatic update distribution services are not yet configured. See [migration evidence](docs/FUNCTION_MIGRATION.md) and [updates](docs/NATIVE_UPDATES.md).

### FAQ

- **Why are some actions unavailable?** Operations remain gated when target identity, component integrity, configuration or explicit confirmation requirements are unmet; check the App's messages and logs.
- **Does a game process prove multiplayer works?** No; the game menu, a single-player mission, EAC and multiplayer are separate acceptance steps.

### Changelog and original script

Changes for the target version are still being reviewed; see the [changelog](CHANGELOG.md). The original Python script and its history remain in the [legacy-script branch](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script), and the repository retains its pinned CoreSnapshot. The original script and Native App have different behavior and requirements. [Original project introduction and historical documentation](https://github.com/LSJOP/helldivers2-fx-launcher/blob/957c8562337fd6715a03ee123e69d29d3950907e/README.md).

### Disclaimer

This community project is not affiliated with the makers of HELLDIVERS 2; names and marks belong to their respective owners. No project-wide source license has been selected. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party components and artwork.
