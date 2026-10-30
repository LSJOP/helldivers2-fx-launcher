# 🤖 AI 辅助安装 / Install with AI

[README](../README.md) · [基础依赖](DEPENDENCIES.md) · [当前版本](../VERSION)

## 简体中文

本指南适用于 ChatGPT、Codex、Claude Code 等能够读取本地文件或指导终端操作的助手。没有本地工具权限的助手应给出操作说明，由用户执行；不得假装已经检查或安装。

当前是源码技术预览。可以自动检查、经用户确认后通过已有 Homebrew 安装 Python/Node.js；**不能据此完成全部游戏运行环境安装**。

### 复制给 AI 助手的完整提示词

将下面整段复制给 ChatGPT、Codex、Claude Code 等助手。请使用你自己的项目目录；无需向助手提供密码、令牌或代理订阅。

```text
请协助我在 Apple Silicon Mac 上准备 HELLDIVERS 2 FX Launcher 源码技术预览。
仓库：https://github.com/LSJOP/helldivers2-fx-launcher

1. 先确认你是否能访问我的本地文件和终端。不能访问时，请逐步指导我执行，并让我返回脱敏结果；不要声称已经检查或安装。确认我解压或克隆的项目文件夹，不要假定下载目录。
2. 在实际项目中阅读 README.md、docs/AI_INSTALL.md、tools/install_dependencies.sh、tools/runtime_paths.sh、tools/check_node.cjs 和依赖检查文件。以当前文件为准，遇到缺失或不一致先报告，不猜测命令或参数。
3. 先做只读检查：uname -s、uname -m，以及 /bin/bash tools/install_dependencies.sh --check。确认原生 Darwin/arm64、Python 3.9+、Node.js 22.0.0+ 及原生 fetch/WebSocket 功能；已满足要求的组件直接跳过。
4. 安装任何软件或修改系统前，先说明准确操作、包名、联网和磁盘影响，并等待我确认。确认后优先使用现有原生 Homebrew，通过 /bin/bash tools/install_dependencies.sh 安装缺失的基础依赖。没有 Homebrew 时让我选择 Homebrew 官方说明或 Python/Node 官方安装包，不自动安装 Homebrew。不要覆盖系统 Python、强制链接、编辑 shell profile 或批量升级软件；密码和系统授权由我自行操作。
5. 安装后重新执行 /bin/bash tools/install_dependencies.sh --check，再执行 /bin/zsh Start.command --check-local。报告实际版本、功能结果和 Python 路径。后者返回 3 表示游戏组件不完整但可进入受限模式，返回 2 表示启动器基础条件有问题；不要把缺失或未验证说成成功。
6. 如需配置语言、外观或 SSH，请通过现有菜单 7、9、8 引导我操作，写入个人设置或保存密码前逐项确认。真实 SSH、FX 环境配置、Steam 和游戏启动需要另外获得我的明确授权。
7. 当前没有完整游戏环境安装包。不要猜测 FX、FEX、Proton 或 gvproxy 的下载地址和兼容版本，不安装来源不明的二进制，不关闭 SIP、Gatekeeper 或其他 macOS 安全保护，不改 DNS、IPv6、防火墙或代理节点。
8. 最后汇报：安装了什么、跳过了什么、验证了什么、仍缺少什么，以及我下一步可以做什么。明确区分“基础依赖就绪”“可打开受限模式菜单”和“游戏运行或联机已验证”。
请优先使用 [3] 的只读安装检测和 docs/SETUP.md；也可运行 /bin/zsh Start.command --setup-check。Guest 未运行或未连接时，FEX/Proton/Steam/游戏必须标为未验证而不是缺失。不要为了保存引导进度改写 settings.json 或丢弃未知字段。已有组件与未知版本均跳过安装，不重装当前可用环境。只有我明确要求导出时才运行 --setup-report；Level 2 连接检查需另行确认。
```

### 可执行范围与确认边界

| 操作 | 是否可直接执行 |
| --- | --- |
| 读取本仓库文档／版本／脚本，检查 uname、Python/Node 版本 | 可以，只读本地信息。 |
| `bash tools/install_dependencies.sh --check` | 可以，只检查 Python/Node，不联网、不安装。 |
| `zsh Start.command --help`、`--check-local` | 可以；后者只检查本地依赖，不建立 SSH 或启动游戏。 |
| 已有原生 Homebrew 安装脚本列出的缺失工具及其依赖 | **先说明准确包名及系统／磁盘／联网影响，取得用户确认**；脚本还会要求输入 y。 |
| 安装 Homebrew、运行官方 .pkg、处理安装权限／密码 | **单独取得用户选择与确认**；本脚本只提供官网选项，不自动安装 Homebrew。需要密码或系统交互时让用户操作。 |
| 改写启动器个人设置或保存密码 | **逐项确认**；使用菜单 7／8／9 的现有功能，不擅自覆盖个人文件。 |
| 启动／配置 FX、建立真实 SSH、启动 Steam／游戏、修改网络 | 不包含在基础依赖安装授权中；必须另获用户明确授权。 |
| 下载未知运行组件，关闭 SIP / Gatekeeper 等保护，修改 DNS／IPv6／防火墙／代理节点 | 本指南不授权，不提供这种安装步骤。 |

用户把安装提示词交给 AI，并不等于同意所有系统修改。已满足条件的组件必须跳过；不要为了“修复”改系统 Python、强制覆盖链接、编辑 shell profile 或批量升级所有 Homebrew 包。

### 1. 定位项目并核实当前文件

请先让用户提供**解压后的项目文件夹**，在该目录工作。阅读 README、此文档和以下实际文件：

- [`tools/install_dependencies.sh`](../tools/install_dependencies.sh)：Apple Silicon 的 Bash 检查／安装入口，支持 `--check`。
- [`tools/runtime_paths.sh`](../tools/runtime_paths.sh)：安装脚本与 Start.command 共用的 Python 和 PATH 规则。
- [`tools/check_node.cjs`](../tools/check_node.cjs)：Node 22.0.0+、原生全局 fetch 与 WebSocket 的本地探针，不连接 URL。
- [`Start.command`](../Start.command)、[`check_dependencies.py`](../tools/check_dependencies.py) 和 [`dependencies.py`](../launcher-20261026/dependencies.py)：基础／运行依赖边界。
- [`VERSION`](../VERSION) 与 [`runtime-requirements.json`](../runtime-requirements.json)：启动器身份和现有兼容组件校验条件；后者不是可用下载地址清单。

若文件缺失或与指南不同，先报告差异。不要编造参数、下载链接或在错误的同名文件夹里运行命令。

### 2. 只读环境检查

在项目根目录运行：

```bash
uname -s
uname -m
/bin/bash tools/install_dependencies.sh --check
```

自动安装脚本仅适用于 Darwin / arm64 原生终端。Python 要求 3.9+；Node 要求 22.0.0+ 且本地功能探针通过。版本号通过不代表全部功能可用，更不代表游戏兼容。探针条件与当前代码一致；Node 原生功能的背景可参考[官方全局对象文档](https://nodejs.org/download/release/v22.15.0/docs/api/globals.html)。

安装脚本返回 0 表示两项满足；`--check` 返回 2 表示缺失、不满足或平台不适用，需看实际输出。此命令不要求 Python 已安装。

### 3. 经确认安装缺失的基础依赖

报告 Python 和 Node 的路径、版本、功能检查结果及将要安装的内容，先询问用户是否同意。获得同意后运行：

```bash
/bin/bash tools/install_dependencies.sh
```

- 已经满足条件：跳过，不重复安装。
- 已有 `/opt/homebrew` 原生 Homebrew：仅安装需要的 `python@3.14` 和／或 `node@24` 以及其 Homebrew 依赖；用户输入 y 才执行。不会自动升级全部包、执行 sudo 或编辑配置文件。
- 没有 Homebrew：提示选择 Homebrew 官方说明或 Python/Node 官方安装包。它只显示链接并退出，不执行 Homebrew 安装器。安装 Homebrew 是另一次需确认的操作。
- 自定义／Intel Homebrew：脚本不改路径，改用官方安装包或交由维护者核实。

官方备用入口：[Homebrew](https://brew.sh/)、[Homebrew 安装说明](https://docs.brew.sh/Installation)、[Python macOS](https://www.python.org/downloads/macos/)、[Node.js](https://nodejs.org/en/download)。下载时选择适用于 macOS / Apple Silicon 的官方安装程序；Node 选择满足要求的 LTS。不要把网络上的一行安装命令直接当作用户已经同意的操作。

### 4. 安装后验证

```bash
/bin/bash tools/install_dependencies.sh --check
/bin/zsh Start.command --check-local
```

第一条必须再次验证版本和功能，输出的 Python 路径应与 Start.command 共用规则一致；无需重新登录或修改 profile。它会识别 Homebrew 版本化 Python 的 `libexec/bin` 和 Node 的 keg-only 路径。

第二条返回 0 表示本地运行检查满足；返回 3 表示基础 UI 可用、游戏运行组件不完整，可使用受限模式；返回 2 表示启动器基础文件问题。**Python/Node 成功安装与游戏可运行是不同结论。**

向用户汇报真实结果：安装了什么、跳过了什么、Python 路径／版本、Node 版本／功能、仍未完成的事项。用户之后可自行双击 Start.command。首次语言自动匹配 macOS；菜单 7 改语言、8 配置 SSH、9 改外观。未经确认不改 SSH、不保存密码、不测试真实连接。

### 5. 当前不能自动完成的部分

完整兼容环境、通用 FX 路径、补丁 FEX/Proton、gvproxy-eim 安装及不同网络适配仍未完成。请查看[依赖说明](DEPENDENCIES.md)。可以说明源码中的版本／哈希条件，不能把它们说成已有一键安装包，也不能猜测下载 URL 或用任意同名组件代替。

### 6. 常见问题

| 问题 | 处理 |
| --- | --- |
| 安装完仍提示缺 Python | 对照安装脚本打印的实际 Python 路径与共用路径脚本；重新解压完整仓库。不要覆盖 `/usr/bin/python3`。 |
| Node 版本旧或缺 fetch / WebSocket | 说明具体失败项；确认是否运行了旧路径，或用户的 NODE_OPTIONS 禁用了功能。不要擅自清除用户环境设置。 |
| Homebrew 下载／构建失败 | 汇报最少量已脱敏错误，停止重复安装；可让用户选择官方安装包。不改镜像、代理或系统网络来强行继续。 |
| 出现密码、安装授权、安全提示 | 让用户自行确认；不索要密码，不绕过安全保护。 |
| Python/Node 就绪，但 `--check-local` 返回 3 | 属于受限模式；列出当前检测的运行组件缺口，不宣称游戏安装完成。 |
| 助手没有本地访问权限 | 提供下一步命令并请用户返回脱敏结果；不要声称已执行。 |

### 验证范围

这些命令与当前脚本接口一致。安装分支用离线模拟 Homebrew 测试，路径和工具探针会本地实测；尚未在全新 Mac 上执行完整真实安装。源预览的实际游戏安装与联机也未在本次验证。AI 应保留这一区别。

## English

This guide works with assistants that can inspect local files or guide Terminal use. Without local access, provide instructions and request redacted results; never claim execution. This source preview can inspect Python/Node and install missing tools through existing Homebrew **after user consent**. It cannot complete the entire game environment.

### Copy the complete prompt

Copy the entire block into ChatGPT, Codex, Claude Code or another assistant. Use your own project folder; do not share passwords, tokens or proxy subscriptions.

```text
Help me prepare the HELLDIVERS 2 FX Launcher source technical preview on an Apple Silicon Mac.
Repository: https://github.com/LSJOP/helldivers2-fx-launcher

1. Confirm whether you can access my local files and Terminal. Without access, guide me one step at a time and request redacted results; never claim you ran checks or installations. Confirm my extracted or cloned project folder instead of assuming its location.
2. Read README.md, docs/AI_INSTALL.md, tools/install_dependencies.sh, tools/runtime_paths.sh, tools/check_node.cjs and the actual dependency-check files. Follow the current repository; report missing or inconsistent files instead of inventing commands or flags.
3. Start with read-only checks: uname -s, uname -m, and /bin/bash tools/install_dependencies.sh --check. Check native Darwin/arm64, Python 3.9+, and Node.js 22.0.0+ with native fetch/WebSocket. Skip tools that already meet the requirements.
4. Before software installation or system changes, explain the exact operations, packages and network/disk impact, then wait for my approval. After approval, prefer existing native Homebrew through /bin/bash tools/install_dependencies.sh to install missing basic dependencies. If Homebrew is absent, let me choose official Homebrew instructions or Python/Node installers; do not install Homebrew automatically. Do not replace system Python, force links, edit shell profiles or upgrade all packages. Let me handle passwords and OS authorization.
5. Rerun /bin/bash tools/install_dependencies.sh --check, followed by /bin/zsh Start.command --check-local. Report actual versions, feature checks and the selected Python path. The latter returns 3 for incomplete game components with limited mode available, or 2 for broken launcher basics. Do not report missing or unverified items as successful.
6. Guide any language, appearance or SSH setup through existing menus 7, 9 and 8. Obtain approval for each personal-setting write or password-storage action. Real SSH, FX environment configuration, Steam and game startup require separate explicit authorization.
7. A complete game environment installer is not available. Do not guess FX, FEX, Proton or gvproxy download URLs or compatible versions, install unknown binaries, disable SIP, Gatekeeper or other macOS protections, or change DNS, IPv6, firewall or proxy nodes.
8. Summarize what was installed, skipped and verified, what remains missing, and my next steps. Distinguish basic dependencies being ready, limited-mode menus being available, and verified gameplay or multiplayer.
Prefer the read-only setup center in [3] and docs/SETUP.md, or /bin/zsh Start.command --setup-check. Uninspected Guest FEX/Proton/Steam/game must remain unverified, never missing. Do not rewrite settings.json or discard unknown fields to remember setup progress. Skip existing components and unknown versions; preserve a working environment. Export --setup-report only on my explicit request. Level 2 connections require separate confirmation.
```

### Permissions

Read-only file/version checks, `bash tools/install_dependencies.sh --check`, `zsh Start.command --help` and `--check-local` may be run without changing the system. Before installation, describe the exact packages and network/disk impact and obtain approval. The installer additionally asks for y. Installing Homebrew, running official package installers, editing personal settings or handling OS permission prompts needs a separate user decision. Hand password entry and OS authorization to the user.

Do not treat the copied prompt as blanket consent. No unknown binaries, guessed runtime URLs, security-protection bypasses, network changes, real SSH, VM/Steam/game startup or credential storage are authorized by this basic setup workflow. Do not replace system Python, force links, edit shell profiles or upgrade every Homebrew package.

### Workflow

1. Locate the user’s extracted project folder. Read this guide, README, the linked installer/shared-path/probe files, dependency logic, VERSION and runtime requirements. Stop and report missing or inconsistent files rather than inventing commands.
2. Run `uname -s`, `uname -m` and `/bin/bash tools/install_dependencies.sh --check`. The installer targets native Darwin/arm64. Python must be 3.9+; Node must be 22.0.0+ with native global fetch and WebSocket. This local probe does not make a network request. Exit 0 means both pass; check-only exit 2 means missing/unsuitable tools or an unsupported platform.
3. Report the paths, versions and failed checks. With explicit consent, run `/bin/bash tools/install_dependencies.sh`. Suitable tools are skipped. Native Homebrew at `/opt/homebrew` installs only the missing `python@3.14` and/or `node@24` plus their dependencies, after confirmation. If Homebrew is absent, the script offers official instructions or package installers and exits; it never installs Homebrew automatically. Custom/Intel prefixes need manual review or official packages.
4. Rerun `/bin/bash tools/install_dependencies.sh --check`, then `/bin/zsh Start.command --check-local`. Installer and shortcut share Python path selection and recognize versioned Homebrew Python and keg-only Node. The second command’s exit 3 means limited mode, not a failed Python/Node installation; exit 2 means broken launcher basics. Game/Guest readiness is separate.
5. Summarize exactly what was installed, skipped and verified, plus remaining gaps. The user can open Start.command; language follows macOS initially, menu 7 changes language, 8 manages SSH and 9 appearance. Do not alter settings or authenticate without consent.

Fallbacks: [Homebrew](https://brew.sh/), [Homebrew installation](https://docs.brew.sh/Installation), [official Python macOS installers](https://www.python.org/downloads/macos/), [official Node.js installers](https://nodejs.org/en/download). Select macOS/Apple Silicon packages and a suitable Node LTS.

### Troubleshooting and incomplete work

For Python selection issues, compare the reported path with the shared runtime-path script; do not overwrite `/usr/bin/python3`. For Node, distinguish an old selected executable from feature-disabling NODE_OPTIONS and request consent before changing user settings. For Homebrew failures, stop repeated installation and offer official packages; do not change proxies, mirrors or system networking. Let the user handle passwords and security prompts without bypasses.

FX discovery, patched FEX/Proton, gvproxy-eim distribution and general networking remain unfinished. Use [dependency documentation](DEPENDENCIES.md#english), never guessed URLs or arbitrary matching names. The installer branches are validated with mocked Homebrew and local probes; a full real installation on a fresh Mac and gameplay/multiplayer are unverified. Successful Python/Node setup is not game installation success.

## 安装检查中心 / Setup center

[完整安装与部署流程 / Full setup and verification workflow](SETUP.md) · [依赖及来源 / Inventory and sources](DEPENDENCIES.md)

默认 [3] 只读检查不会连接 Guest；原有运行检查需要单独选择与确认。无状态引导不调用配置保存器。CLI --setup-check 仅静态检查，--setup-report 明确新建私有脱敏报告。旧 --check/--report 不是纯静态工具。

Default [3] is local-only; the existing runtime check is a separate confirmed choice. Stateless guidance never saves configuration. --setup-check is static; --setup-report explicitly creates a new sanitized private report. Old --check/--report are not purely static.
