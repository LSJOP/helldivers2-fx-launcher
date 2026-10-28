# 详细依赖 / Dependency details

[返回中文教程](../README.md#简体中文) · [Back to the English guide](../README.md#english)

## 简体中文

这是给已经有兼容环境的用户看的补充说明。**完整安装包仍在准备中，新玩家目前无法仅靠本仓库完成安装。**

### 电脑上需要什么

- 搭载 Apple 芯片（M 系列）的 Mac。具体最低 macOS 版本尚未验证。
- Python 3.9 或更新版本用于启动器；Node.js 22.0.0+，具备全局 `fetch` 和 `WebSocket` 功能 用于运行操作，缺少时仍能进入菜单。
- 匹配的 FX 应用及虚拟机网络组件。启动器依照精确的文件校验值检查兼容性；这些游戏组件缺失时仍可使用菜单。
- 虚拟机内部匹配的 FEX、Proton/Wine；自己的 Steam 账号和游戏。

当前使用的版本基线是 FX 1.9.4 和 Proton-JE `11.0-20261014-3`，但仍有本地补丁。**相同版本号不代表所有组件都已匹配。** [FX 1.9.4 官方发布页](https://github.com/fxgl/steamac/releases/tag/v1.9.4)仅供了解该版本；下载普通发行版不能替代尚缺的完整兼容组件包。

### 哪些缺失会进入受限模式

| 所需文件／组件 | 当前状态 |
| --- | --- |
| `performance-stutter-20261027/FX HUD隔离诊断.app` | 不包含在本次下载中；普通安装位置暂未自动适配。 |
| `goal-fx-multiplayer-20261026/gvproxy-eim` | 不包含二进制；只保留启动 wrapper。 |
| Guest Proton-JE / FEX / Wine | 需要匹配补丁，自动下载与安装尚未提供。 |

高级用户可在 [`runtime-requirements.json`](../runtime-requirements.json) 查看当前校验条件。请勿删除文件校验来跳过缺失组件；校验通过也不证明游戏或联机成功。

### 当前网络限制

发布目标是让玩家使用各自的网络。当前代码尚固定本机代理端口 `7890` 和 Guest 到 Host 的 `192.168.127.254:7890`，也保留 TUN / FlClash 分支。直连、其他代理软件与自定义端口的通用适配尚未完成。

CPU / 内存配置也保留原有预算：8 CPU、8 GiB 虚拟机内存、6 GiB 显存预算，尚不能视为所有 Mac 的通用设置。

### 个人信息保存在哪里

SSH 设置保存在 `~/Library/Application Support/Helldivers2FXLauncher/`。只有选择记住密码时，才会使用 macOS 钥匙串。不要分享这个用户目录、Steam 登录文件、虚拟机磁盘、SSH 密钥、代理配置或订阅。

## English

This page is for users who already have a compatible environment. **The full setup package is still being prepared; this repository alone cannot set up a fresh Mac.**

### Required components

- A Mac with Apple silicon (M-series chip). The minimum macOS version is unverified.
- Python 3.9 or newer, and Node.js 22.0.0+ with global `fetch` and `WebSocket`. Python is needed for the launcher; Node.js is only required for runtime actions.
- A matching FX application and virtual-machine network component. Compatibility checks use exact file hashes; missing runtime components do not block the menu.
- Matching FEX and Proton/Wine components inside the virtual machine, plus your own Steam account and game.

The version baseline is FX 1.9.4 and Proton-JE `11.0-20261014-3`, with additional local patches. **Matching version numbers alone do not satisfy the component checks.** The [official FX 1.9.4 release page](https://github.com/fxgl/steamac/releases/tag/v1.9.4) identifies the baseline; the ordinary release does not replace the missing full compatibility package.

### Which missing components enable limited mode

| Required file or component | Current status |
| --- | --- |
| `performance-stutter-20261027/FX HUD隔离诊断.app` | Excluded from this download; automatic discovery of normal installation locations is unfinished. |
| `goal-fx-multiplayer-20261026/gvproxy-eim` | Binary excluded; only its wrapper is included. |
| Guest Proton-JE / FEX / Wine | Matching patches are required; automatic download and installation are unavailable. |

Advanced users can inspect the current checks in [`runtime-requirements.json`](../runtime-requirements.json). Do not remove hash checks to bypass missing components. A matching hash does not verify the game or multiplayer.

### Current network and resource limitations

The intended release will use each player’s own network. The current code still assumes local proxy port `7890` and a Guest-to-Host proxy at `192.168.127.254:7890`, with TUN / FlClash branches. General support for direct connections, other proxy applications and custom ports is unfinished.

The existing resource budget is 8 CPUs, 8 GiB guest RAM and a 6 GiB advertised GPU budget. Its suitability across Mac models is unverified.

### Your personal information

SSH settings are stored under `~/Library/Application Support/Helldivers2FXLauncher/`. Password storage uses macOS Keychain only when you opt in. Do not share that user directory, Steam login files, virtual-machine disks, SSH keys or proxy configurations and subscriptions.

首次语言识别通过 macOS CoreFoundation 只读取 AppleLanguages，不需要 Node、SSH 或网络；保存的手动选择优先，检测失败静默回退到 English。

First-run language matching reads AppleLanguages through native CoreFoundation only. Saved manual choices take precedence; failures fall back silently to English. No Node, SSH or network is needed.

Python/Node 自动检查与安装只通过已有 Homebrew 完成，并先征得用户确认；详细操作见 [AI 安装指南](AI_INSTALL.md)。无 Homebrew 时提供官方安装包选项，不自动安装 Homebrew。

See the [AI installation guide](AI_INSTALL.md#english) for confirmed Python/Node setup using existing Homebrew. No Homebrew bootstrap or game-runtime installation is performed automatically.
