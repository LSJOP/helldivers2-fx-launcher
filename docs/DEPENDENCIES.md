# 安装依赖完整清单 / Installation dependency inventory

[README](../README.md) · [安装流程 / Setup](SETUP.md) · [用户数据 / User data](USER_DATA.md)

## 简体中文

这是源码 Preview。完整全新 Mac 游戏部署尚未实现。下表来自当前入口、后端、运行脚本和 [`runtime-requirements.json`](../runtime-requirements.json) 的 `installation_audit`；该节为审计元数据，不是新的运行参数。

**已验证安装步骤**：Shell/Python/Node 的路径选择、跳过已满足工具、确认及复查流程通过隔离模拟；这不等于在新 Mac 实装成功。Python 历史测试版本为 3.9.6。

**仅指导／待确认**：FX 专用补丁包、EIM 构建、匹配 FEX/Proton-JE/Wine 和 Guest 映像的完整来源与可复现步骤。普通 FX 或上游最新版不能替代 manifest 指定产物。[FX 1.9.4 官方页面](https://github.com/fxgl/steamac/releases/tag/v1.9.4)仅表明历史基线；不代表整个专用环境可下载、可再分发或已适配其他 Mac。

## English

This is a source Preview, not a complete fresh-Mac game installer. The table is generated from descriptive `installation_audit` metadata in the existing manifest and actual launch calls; it does not change runtime settings.

The tool-helper/path/skip/confirmation/recheck workflow has isolated simulation coverage, **not fresh-Mac installation proof**. Python 3.9.6 is historical test evidence. Matching patched FX, EIM, FEX, Proton/Wine and Guest build provenance/recipes remain incomplete; an upstream release is a reference, not a verified substitute.

## 依赖表 / Dependency table

| 名称 / Name | 用途 / Purpose | 必需性 / Necessity | 检测方式 / Detection | 官方来源 / Source | 安装方式 / Installation | 版本证据 / Version | 仓库包含 / Included |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Apple Silicon / macOS | 启动器目标平台；其他平台不承诺支持 / target platform | 必需（目标平台） / required target | platform + sysctl；不启动虚拟机 | [上游 / Official](https://support.apple.com/mac) | 用户已有系统；不自动更改 / manual | 最低 macOS 未验证 / minimum macOS unverified | 否 / No |
| zsh / Bash / Terminal | 双击入口和基础依赖安装辅助 / entry and tool helper | 必需；Bash 仅安装辅助 / required; Bash for helper | Shell 语法检查；macOS 系统工具路径 | [上游 / Official](https://support.apple.com/guide/terminal/welcome/mac) | macOS 自带 / OS-provided | 现有脚本语法；未建立其他 Shell 兼容范围 / current syntax only | 否 / No |
| Python + standard library | 终端 UI、设置、诊断及 JSON/SSL/ctypes 等 / launcher and stdlib | 必需 / required | Start.command 共用路径规则；sys.version_info >= (3,9)；基础源码 AST 检查 | [上游 / Official](https://www.python.org/downloads/macos/) | 已有 Homebrew 经确认；或官方安装包 / consented existing brew or manual | >=3.9；历史测试 3.9.6；所有新版本兼容性未逐一验证 / not every newer version tested | 否 / No |
| Launcher sources / locales / emblems | 完整菜单与本地帮助资源 / UI and local resources | 必需 / required | dependencies.launcher_problems；文件可读和语法检查，不是签名校验 | [上游 / Official](https://github.com/LSJOP/helldivers2-fx-launcher) | 完整 ZIP / git clone；不覆盖自定义文件 / extract separately | 由根 VERSION 标识 / root VERSION | 是 / Yes |
| Node.js | steam-cdp.mjs 的 fetch / WebSocket / Steam CDP | 游戏控制必需；浏览可缺 / runtime only | tools/check_node.cjs 本地功能探针；无网络请求 | [上游 / Official](https://nodejs.org/en/download) | 已有 Homebrew 经确认；或官方安装包 / consented brew or manual | >=22.0.0 + fetch + WebSocket；不只看版本 / capability check | 否 / No |
| OpenSSH client | Guest SSH 与本地 CDP 转发 / Guest transport | 运行必需；浏览可缺 / runtime only | 本机 executable lookup；连接需主动 Level 2 | [上游 / Official](https://www.openssh.com/) | macOS 自带；缺失交由用户核实 / OS-provided | 未固定 OpenSSH 版本；实际连接另验 / no pinned version | 否 / No |
| macOS native tools | open、pgrep/ps、scutil 等；hardware sysctl / system_profiler | 按运行分支必需 / conditional runtime | 调用关系静态审计；本次不触发运行或网络工具 | [上游 / Official](https://support.apple.com/guide/terminal/welcome/mac) | macOS 自带 / OS-provided | 具体最低系统版本未验证 / unverified OS minimum | 否 / No |
| macOS Keychain / security | 仅用户选择记住 SSH 密码时使用 / optional password storage | 可选 / optional | 本次不读取或测试凭据；沿用原机制 | [上游 / Official](https://support.apple.com/guide/keychain-access/welcome/mac) | macOS 自带；用户主动选择 / opt-in | 既有 service 标识，不迁移 / existing reference unchanged | 否 / No |
| Homebrew | 仅辅助准备 Python / Node / tool installer | 可选；不是运行依赖 / optional | 检查已有原生 /opt/homebrew；不运行安装器 | [上游 / Official](https://docs.brew.sh/Installation) | 用户自行确认安装；本项目不自动安装 / manual | 现有安装器要求原生标准 prefix；新装 Mac 未验 / fresh Mac unverified | 否 / No |
| FX / steamac-vm + Guest image / graphics | 虚拟机、Guest 及匹配图形实现 / virtual machine | 游戏必需；不阻止 UI / game only | manifest 指定位置、执行权限与 SHA-256；不启动 | [上游 / Official](https://github.com/fxgl/steamac/releases/tag/v1.9.4) | 精确补丁包与可复现安装来源待确认 / matching package pending | 历史 FX 1.9.4 + 本地补丁；普通 1.9.4 不等价 / patched baseline | 否 / No |
| gvproxy-eim + wrapper | EIM 虚拟机网络 / VM networking | 当前链路必需 / current runtime | binary hash + binary/wrapper executable；不启动 | [上游 / Official](https://github.com/containers/gvisor-tap-vsock) | EIM 补丁构建与来源待确认；不下载 / provenance pending | 精确哈希见 manifest；无已确认通用版本 / hash-specific | 仅 wrapper / Wrapper only |
| FEX | Guest x86-64 指令转换 / translation | 游戏必需；本机未验证 / game only | 本机不查；Guest 路径/哈希由现有后端检查 | [上游 / Official](https://github.com/StonkGuy/FEX) | 维护者确认精确补丁/构建后手动准备；流程未闭合 / pending | 精确 hash，版本号未确认；不能用 latest 替代 / no generic version | 否 / No |
| Proton-JE / patched Wine | Guest Windows 兼容 / compatibility | 游戏必需；本机未验证 / game only | 本机不查；既有后端比对 FEX/ntdll/Wine core hash、tool mapping | [上游 / Official](https://github.com/jegglest/proton-je) | 匹配补丁产物手动准备，安装配方待确认 / matching build pending | 11.0-20261014-3 历史基线 + hash；非普通包保证 / hash-specific | 否 / No |
| Guest Python / systemd / Linux tools | 远程 python3、systemctl --user、taskset、pgrep、procfs、sysctl 等 / backend primitives | 按现有链路必需 / runtime | 本机不查；部分由原后端实际命令验证；无完整独立能力探针 | [上游 / Official](https://github.com/fxgl/steamac) | 兼容 Guest 中准备；不在本机安装 / matching Guest | 未建立全部最低版本或可复现 Guest 清单 / unverified full baseline | 否 / No |
| Steam | Guest 用户服务、登录、CDP 和游戏分发 / client | 游戏必需 / game | 本机不查；原检查查询进程、登录证据与 CDP；需主动操作 | [上游 / Official](https://store.steampowered.com/about/) | 用户在兼容 Guest 内安装与登录 / manual | Guest 服务/CDP 约定；具体 Steam build 未固定 / not pinned | 否 / No |
| HELLDIVERS 2 / EAC | 合法游戏内容及其自带 EAC / owned game | 游戏必需 / game | 本机不查；原后端请求 app 553850、观察进程/EAC，不是完整文件验证 | [上游 / Official](https://store.steampowered.com/app/553850/HELLDIVERS_2/) | 用户通过 Steam 安装；本项目不分发 / manual | 具体游戏 build 未固定；EAC/联机需分别验收 / not pinned | 否 / No |
| Network / existing proxy assumptions | Steam 登录、PlayFab、多人联机；更新查询按需联网 / connectivity | 游戏/联网功能按需；本地 UI 不需要 / conditional | 安装 Level1 不探测；现有网络诊断仅主动选择 | [上游 / Official](https://github.com/LSJOP/helldivers2-fx-launcher) | 使用自己的网络；不自动配置 / user-owned network | 当前代码代理端口7890等假设非通用安装要求；直连适配未完成 / not universal | 否 / No |

## 精确路径与校验 / Exact locations and hashes

以 manifest 的 `components` 为准：

- FX: `performance-stutter-20261027/FX HUD隔离诊断.app/Contents/MacOS/steamac-vm`。
- gvproxy-eim: `goal-fx-multiplayer-20261026/gvproxy-eim`；wrapper 已提供，二进制不包含。
- Guest FEX: `~/.local/share/Steam/steamapps/common/FEX-Emu/usr/bin/FEX`。
- Guest Proton-JE: `~/.local/share/Steam/compatibilitytools.d/proton-je-11.0-20261014-3`，还需匹配其 Wine core/ntdll hashes。

本机“要求位置未找到”不证明其他位置没有安装；**不要自动重装或移动已有可用实例**。文件存在、可执行、哈希匹配、版本匹配、实际可用是不同结论。FEX/Proton/Steam/游戏在 Level 1 全部保持未验证，即使本机所有文件匹配。

Use `components` in the manifest for authoritative paths/hashes. A missing configured path does not prove global absence. Existing installations are skipped, unknown versions are not overwritten, and all Guest components remain unverified in Level 1. A matched file hash is not runtime or multiplayer evidence.

## 当前运行限制 / Runtime limitations

本次保留固定 8 CPU、8192 MiB Guest RAM、6144 MiB GPU budget；性能菜单的 UserDefaults 不取代启动参数。现有网络链路仍保留代理端口 `7890`、Guest 网关 `192.168.127.254` 及 TUN / FlClash 分支；这些是当前实现限制，不是让玩家复制作者网络的安装要求。直连、自定义端口、通用 FX 路径仍未闭合。不要为检测而改变网络、安全保护或兼容组件。

The existing 8 CPU / 8192 MiB RAM / 6144 MiB GPU launch budget and proxy/TUN assumptions remain unchanged. Direct/custom-proxy support and general FX discovery are unfinished. Do not alter network/security/compatibility settings merely to pass a static check.

## 配置位置与隐私 / Configuration and privacy

[用户数据清单](USER_DATA.md)记录设置、Keychain、性能偏好、网络快照和历史的实际存储位置；`HD2FX_SETTINGS_FILE` 可以改变设置路径。安装引导不读取密码、Keychain 或原始诊断历史，不调用设置保存器。新安装报告位于设置文件同目录的 `reports/installation/`，仅在主动导出时新建 0600 文件，不覆盖旧报告。

See [user data inventory](USER_DATA.md) for actual paths and overrides. The guide never saves settings or reads credentials/history. Reports are new private files under `reports/installation/` alongside the settings file, created only on request. Native AppleLanguages detection needs no Node, SSH or network; saved manual language choices retain priority.

Node 路径检查保留现有 PATH、Homebrew、`/usr/local` 和可选 Codex 缓存回退；普通玩家不需要安装 Codex 或复制作者目录。 / Node lookup retains the existing PATH/Homebrew/usr-local and optional Codex-cache fallback. Players do not need Codex or the author’s directories.
