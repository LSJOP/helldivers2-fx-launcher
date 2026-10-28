# HELLDIVERS 2 · Mac 启动助手 / Mac Launcher

[简体中文](#简体中文) · [English](#english)

**预览版：首次安装流程尚未完成。 / Preview: full setup for new players is not ready yet.**

## 简体中文

### 先看这里：现在能直接玩吗？

**当前下载包还不能让一台全新的 Mac 直接运行游戏。** 它需要匹配的 FX 虚拟机和兼容组件，而完整组件包及自动安装流程还在准备中。只下载普通 FX 并不够。

如果你是第一次安装，可以先下载并打开启动入口查看缺少什么；遇到“完整兼容组件包目前尚未提供下载”，请停在这里，等待完整安装版本。这不是你的操作错误，也不需要反复重装或更改网络。

已有相同兼容环境的玩家，可以继续下面的步骤。这里不包含游戏，需使用自己的 Steam 账号与游戏。

### 第 1 步：下载完整文件夹

1. 在本页上方点击绿色的 **Code** 按钮。
2. 选择 **Download ZIP**，下载完成后双击 ZIP 解压。
3. 把解压后的整个文件夹放到你方便找到的位置，例如“文稿”。

请保留整个文件夹；启动文件需要用到旁边的其他文件。

### 第 2 步：双击启动入口

打开刚解压的文件夹，双击 **`启动绝地潜兵2.command`**。

英文名 **`Start.command`** 也可以，两者打开同一个启动器，只需选一个。你不需要打开 `.py` 文件，也不需要运行测试。

会弹出一个“终端”窗口，先检查这台 Mac 上是否有需要的程序和文件：

| 提示 | 怎么做 |
| --- | --- |
| `OK / 已就绪` | 这项本地检查通过，继续看下一项。 |
| `NEEDED / 需要准备`，提到 Python | 到 [Python 官方 macOS 下载页](https://www.python.org/downloads/macos/)下载并安装 Python 3.9 或更新版本，然后再次双击入口。 |
| `NEEDED / 需要准备`，提到 Node.js | 到 [Node.js 官方下载页](https://nodejs.org/en/download)，选择 macOS 安装程序，安装当前 LTS 版本后再次打开入口。 |
| 提到 FX 或虚拟机网络组件 | 当前包缺少完整兼容组件。新玩家请等待完整安装版本；高级用户可查看[详细依赖](docs/DEPENDENCIES.md)。 |

检查失败会停在这里，**不会连接虚拟机或启动游戏**。窗口会保留提示，按回车即可关闭。

这套方案面向搭载 Apple 芯片（M 系列）的 Mac；Intel Mac 与不同 macOS 版本的适配尚未验证。通过本地检查也不代表游戏已能运行。

### 第 3 步：第一次进入菜单

只有本地检查通过，才会进入启动器菜单。

1. 选择界面语言。
2. 按提示填写虚拟机的 **SSH 连接信息**。SSH 是让脚本连接到虚拟机的方式，账号信息应来自你安装的 FX 环境。
3. 默认显示 `127.0.0.1`、端口 `2222`、用户名 `steamos`。请以自己的 FX 设置为准。密码输入时不显示字符，输入完按回车即可。
4. 是否记住密码由你选择。选择记住时使用 macOS 钥匙串保存。
5. 在 FX 的 Steam 窗口中用自己的账号登录，并确认已安装 HELLDIVERS 2。
6. 回到脚本菜单，选择 **1「启动游戏」**，根据提示在 FX 窗口继续操作。

菜单常用项：**1 启动游戏、3 检查运行环境、7 切换语言、8 修改 SSH、0 退出菜单**。选择 0 退出菜单不会关闭正在运行的游戏。

启动或配置环境时，脚本可能打开 FX、调整虚拟机网络、重启虚拟机里的 Steam、更新游戏启动项。菜单 2 会调整 FX 性能设置；网络菜单中的有线方案可能关闭 Wi-Fi，请先看清具体提示。

### 网络需要怎么设置？

**每位玩家使用自己的网络、代理和节点，不需要复制作者的网络配置。**

不过，当前预览版代码仍依赖代理端口 `7890`，还没有完成直连和自定义代理的通用适配。遇到相关提示时，请先查看[当前限制](docs/DEPENDENCIES.md)，不要为了通过检查而随意关闭 Wi-Fi、IPv6 或切换节点。

游戏成功打开和多人联机成功是两项不同的结果；“未确认”表示脚本还没有取得足够证据。

### 遇到问题怎么办？

- **提示缺少文件：**重新下载并解压整个 ZIP，再从新文件夹打开入口。
- **提示兼容组件缺失：**当前安装包尚不完整，请等待后续版本。
- **双击提示没有执行权限：**打开“终端”，输入 `zsh` 后留一个空格，把 `Start.command` 拖进窗口，再按回车。
- **SSH 连接失败：**确认 FX 虚拟机已启动，在菜单 8 核对自己的连接信息。
- **游戏已启动但无法联机：**先检查自己的 Steam 连接与网络；启动成功不代表联机已经验证。
- **需要求助：**到本仓库上方的 [Issues](https://github.com/LSJOP/helldivers2-fx-launcher/issues) 页面，点击 **New issue**。说明 Mac 型号、macOS 版本、停在哪一步和错误文字，遮住密码、账号和代理订阅。

## English

### Can I play with this download right now?

**A complete setup for a fresh Mac is not available yet.** This launcher needs a matching FX virtual machine and compatibility components. The full component package and automatic setup are still being prepared. Installing ordinary FX alone is not enough.

If this is your first installation, you can open the shortcut to see what is missing. If it says “The full compatibility package is not available in this download yet,” stop there and wait for the complete setup release. Reinstalling everything or changing your network will not supply those missing files.

Players who already have the matching environment can follow the steps below. You need your own Steam account and game installation.

### Step 1: Download the whole folder

1. Click the green **Code** button near the top of this page.
2. Choose **Download ZIP**. When it finishes, double-click the ZIP to extract it.
3. Move the entire extracted folder somewhere easy to find, such as Documents.

Keep the folder together. The shortcut needs the other files beside it.

### Step 2: Open the shortcut

Open the extracted folder and double-click **`Start.command`**.

The Chinese shortcut, **`启动绝地潜兵2.command`**, opens the same launcher. Use either one. You do not need to open any `.py` files or run tests.

A Terminal window opens and checks the programs and files needed on this Mac:

| Message | What to do |
| --- | --- |
| `OK / 已就绪` | This local check passed. Read the next line. |
| Python is needed | Download Python 3.9 or newer from the [official Python macOS page](https://www.python.org/downloads/macos/), install it, and open the shortcut again. |
| Node.js is needed | Visit the [official Node.js download page](https://nodejs.org/en/download), select the macOS installer for the current LTS version, install it, and reopen the shortcut. |
| FX or the virtual-machine network component is needed | The complete compatibility package is missing. New players should wait for the full setup release. Advanced users can read the [dependency details](docs/DEPENDENCIES.md#english). |

If a check fails, the shortcut stops **before connecting to the virtual machine or starting the game**. The window keeps the message visible; press Return to close it.

This project targets Macs with Apple silicon (M-series chips). Intel Macs and compatibility across macOS versions are unverified. Passing local checks does not verify game compatibility.

### Step 3: Use the launcher for the first time

The menu opens after local checks pass.

1. Choose your interface language.
2. Enter your virtual machine’s **SSH connection details** when asked. SSH lets the script communicate with the virtual machine; use the details supplied by your FX environment.
3. The initial values are `127.0.0.1`, port `2222`, and username `steamos`. Check these against your own FX setup. Password characters are hidden while typing; press Return when finished.
4. Choose whether to remember the password. Opting in stores it in macOS Keychain.
5. Sign in to Steam inside FX with your own account and make sure HELLDIVERS 2 is installed.
6. Return to the launcher and choose **1: Start game**. Follow any further prompts in the FX window.

Common menu items: **1 Start game, 3 Check environment, 7 Language, 8 SSH settings, 0 Exit menu**. Exiting the menu with 0 leaves a running game open.

Launching or preparing the environment can open FX, adjust guest networking, restart Steam inside the virtual machine and update game launch options. Menu 2 changes FX performance settings. The wired-network action in the network menu can turn off Wi-Fi; read its prompts before using it.

### What about my network?

**Use your own network, proxy and node selection. You do not need the author’s personal network configuration.**

The preview code still requires proxy port `7890`; support for direct connections and custom proxy settings is unfinished. Read the [current limitations](docs/DEPENDENCIES.md#english) if this blocks you. Changing Wi-Fi, IPv6 or proxy nodes just to pass a check is not part of the beginner setup.

Starting the game and successfully joining multiplayer are separate outcomes. “Unverified” means the launcher has not obtained enough evidence.

### Troubleshooting

- **Missing project files:** download and extract the whole ZIP again, then use the shortcut in the new folder.
- **Missing compatibility components:** wait for the complete setup release.
- **No execution permission:** open Terminal, type `zsh` followed by a space, drag `Start.command` into the window, and press Return.
- **SSH connection failed:** make sure FX is running and check your connection details in menu 8.
- **Game opens but multiplayer fails:** check your Steam connection and network. Game startup does not verify multiplayer.
- **Need help:** open [Issues](https://github.com/LSJOP/helldivers2-fx-launcher/issues), click **New issue**, and include your Mac model, macOS version, the step you reached and the error text. Hide passwords, account details and proxy subscriptions.

---

[第三方说明 / Third-party notices](THIRD_PARTY_NOTICES.md) · No project-wide open-source license has been selected yet. / 项目源码的开源许可证尚未确定。
