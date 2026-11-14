<div align="center">
  <img src="docs/assets/app-icon.png" width="128" alt="HD2FXNative icon">
  <h1>HD2FXNative</h1>
  <p>HELLDIVERS 2 FX Launcher · Apple Silicon macOS</p>
</div>

[简体中文](README.zh-CN.md) | [English](README.md)

## 简体中文

HD2FXNative 是面向 Apple Silicon Mac 的第三方社区启动与管理工具，使用 SwiftUI 和原生核心，帮助用户检查 FX 环境、配置运行环境和管理游戏性能设置。

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

### 下载与安装

**发布目标：HD2FXNative v1.0.0。** GitHub 尚无已发布版本。已检查的本地 App 为 `0.1.0`、arm64，采用 ad hoc 签名，无 Developer ID，Apple 公证未获验证。Gatekeeper 可能拦截下载的副本。公开 DMG 及其 SHA-256 待发布。[GitHub Releases](https://github.com/LSJOP/helldivers2-fx-launcher/releases)

发布后，可在运行 macOS 14 或更高版本的 Apple Silicon Mac 上安装。

1. 从正式 Release 下载 macOS arm64 DMG。
2. 运行 `shasum -a 256 <下载的 DMG>`，与发布说明中的 SHA-256 比对。匹配后打开 DMG。
3. 将 HD2FXNative 拖入「应用程序」。
4. 打开 HD2FXNative。
5. 在 FX 管理中选择已安装的 FX Steam Launcher，按首次运行向导操作。SteamOS 内须安装 Steam 和 HELLDIVERS 2（AppID 553850），使用拥有游戏的账号，并确保 Guest 可通过 SSH 访问。在 App 内输入所需凭据并审核拟执行的变更。
6. 在总览点击「启动 HELLDIVERS 2」。

从源码构建请参阅[开发指南](docs/NATIVE_DEVELOPMENT.md)。

### 主要功能

- 从总览发起带保护检查的 HELLDIVERS 2 启动流程。FX 管理检查所选 FX 安装并提供受支持的 FX／Steam 操作。
- 首次运行环境配置检查 Guest 身份、运行能力和组件完整性。经确认后可安装固定版本的 Proton-JE、选择已验证的 Steam 兼容工具，并合并启动参数以保留自定义参数。检测为只读，部署与恢复各有检查条件。
- 运行环境页面报告 FEX 和 Proton-JE 的检测依据。SSH 和 sudo 凭据可分别在已验证目标及会话的进程内存中复用。
- Swift App 提供七个原生页面、日志、限定范围的性能设置和十种界面语言。SteamOS 内的可选安装步骤需要 Python 3。
- 设置集成 Sparkle 更新功能。公开更新服务和端到端安装仍待验证。

### 已知问题

- FX 和 SteamOS 兼容性取决于所选构建和实测能力。当前启动路径有已记录的代理不匹配问题。安全停止或重启 FX 暂不可用。
- 实验性 FEX 候选曾在真实 Guest 中构建成功，但可执行文件的哈希未通过部署审核。候选的安装、恢复和游戏兼容性均待验证。其他 Proton-JE 构建和全新 SteamOS 部署仍需验收。
- 11 月 5 日的历史 Native 构建曾进入游戏主菜单／舰桥。正式包启动、单人任务、EAC 和多人联机仍需分别验证。
- 公开分发、Gatekeeper 实际行为和签名自动更新仍待验收。已检查的本地 App 使用 ad hoc 签名，公证未获验证。
- [验收报告](docs/acceptance/RELEASE_READINESS_REPORT.md) · [已知问题详情](docs/acceptance/KNOWN_ISSUES.md) · [首次运行验收](docs/testing/NATIVE_FIRST_RUN_ACCEPTANCE.md) · [更新机制](docs/NATIVE_UPDATES.md) · [性能设置限制](docs/GAME_PERFORMANCE.md)

### 更新日志

未发布变更包括总览启动、首次运行 Proton-JE 校验及 Steam 配置、实验性 FEX 审核及恢复，以及 SSH 认证修复。参见[更新日志](CHANGELOG.zh-CN.md)和[原版启动器历史](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script)。

### 免责声明

本项目由社区开发，与 HELLDIVERS 2 官方无关联，相关名称及商标属于各自权利人。项目尚未选定全项目源码许可证；第三方组件与素材说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

### 文档

使用与开发指南、架构说明和历史报告见[文档索引](docs/README.md)。

接续开发请读取[当前状态](docs/DEVELOPMENT_STATUS.md)和[交接文档](docs/NATIVE_APP_DEVELOPMENT_HANDOFF.md)，以 main 源码与 AGENTS.md 为准，未合并候选及实机验收单独记录。
