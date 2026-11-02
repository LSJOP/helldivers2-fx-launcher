<div align="center">
  <img src="docs/assets/app-icon.png" width="128" alt="HELLDIVERS 2 FX Launcher 图标">
  <h1>HELLDIVERS 2 FX Launcher</h1>
  <p>为 Apple Silicon Mac 打造的 HELLDIVERS 2 FX 启动与管理工具。</p>
</div>

<a id="简体中文"></a>

[**English**](README.md) | [**简体中文**](README.zh-CN.md)

![macOS](https://img.shields.io/badge/macOS-14%2B-0078D4?style=flat-square&labelColor=171A1F)
![Apple Silicon](https://img.shields.io/badge/Platform-Apple%20Silicon-0078D4?style=flat-square&labelColor=171A1F)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0078D4?style=flat-square&labelColor=171A1F)
![状态](https://img.shields.io/badge/Status-Development%20Preview-F29D38?style=flat-square&labelColor=171A1F)
![版本](https://img.shields.io/badge/Native-0.1.0-FFD600?style=flat-square&labelColor=171A1F)

[软件截图](#zh-screenshots) · [主要功能](#zh-features) · [下载安装](#zh-installation) · [快速开始](#zh-usage) · [兼容性](#zh-development) · [原脚本](#zh-legacy)

<a id="zh-overview"></a>

以 **SwiftUI + AppKit** 构建的原生界面，通过原有 Python Core 启动游戏、检查所选 FX 环境、读取性能配置。六个页面职责清晰，默认深色，操作进度和结果在页面内显示，技术细节按需展开。

> [!IMPORTANT]
> **开发预览。** 正式安装包尚未发布。已完成的 Native 成果已整合到 [main](https://github.com/LSJOP/helldivers2-fx-launcher/tree/main)；[feature/macos-native-app](https://github.com/LSJOP/helldivers2-fx-launcher/tree/feature/macos-native-app) 保留开发历史。仓库不包含运行时二进制、游戏文件或 Guest 镜像。

<a id="zh-screenshots"></a>

## 软件截图

[![总览](docs/images/dashboard.png)](docs/images/dashboard.png)

| 运行环境 | FX 管理 |
| --- | --- |
| [![运行环境](docs/images/environment.png)](docs/images/environment.png) | [![FX 管理](docs/images/fx-manager.png)](docs/images/fx-manager.png) |

<details>
<summary>游戏性能配置</summary>

[![游戏性能配置](docs/images/performance.png)](docs/images/performance.png)

</details>

四张均为 2026-11-03 的真实 Debug App 窗口截图；界面没有合成。图标与插画为 App 内展示的素材，不是生成的软件截图。截图不证明 Guest、游戏或联机就绪。FX 自动选择界面在本次验证后更新。

<a id="zh-features"></a>

## 主要功能

| 状态 | 功能 |
| --- | --- |
| 🟢 已实现 | 六页原生界面、Cmd+1…6 导航、深色／浅色／跟随系统、正式项目图标 |
| 🟢 已实现 | 限定范围本机／FX 发现；带校验、修订检查、备份和原子替换的配置编辑 |
| 🟢 已实现 | 可搜索、筛选、有容量限制且脱敏的日志与诊断报告 |
| 🟢 已实现 · 只读 | 游戏性能配置页的真实芯片／CPU／GPU／内存检测、当前 FX 偏好和基准差异 |
| 🟠 开发中 | 一键检测与 SSH 后台操作；原入口 FX／Steam 启动、SSH／sudo 独立凭据复用；新入口实机验收仍待完成 |
| 🟢 已实现 · 静态覆盖检查通过 | 原 Python 十语言资源单独保留；Native 统一资源覆盖全部十语言。缺失文案明确显示缺失键，不回退英文；译文自然度仍需人工审校 |
| ⚪ 计划中／不可用 | 安全停止／重启 FX、可写推算配置与限定参数恢复、签名／公证安装包 |

性能规则完全本地、可复现。原记录中的 **M4 Pro／24 GiB** 配置仅是候选基准，不代表全面性能验收。其他硬件不生成可写推算配置；应用／恢复明确禁用并显示原因。见[参数来源与限制](docs/GAME_PERFORMANCE.md)。

<a id="zh-requirements"></a>
<a id="zh-installation"></a>

## 下载与安装

**正式安装包尚未发布。** 仓库 [Releases 页面](https://github.com/LSJOP/helldivers2-fx-launcher/releases) 当前没有已发布版本；此链接不是不存在的安装包下载按钮。

源码预览需要 **Apple Silicon、macOS 14+、完整 Xcode／macOS SDK、Python 3.9+**。游戏操作还需要既有完整旧启动器目录、原验证组合中的 FX／gvproxy 资源和可用的 Guest 认证配置。

```sh
git clone --branch main --recurse-submodules https://github.com/LSJOP/helldivers2-fx-launcher.git
cd helldivers2-fx-launcher/native-app
./script/build_and_run.sh --xcode-only
open build/Debug/HD2FXNative.app
```

已有克隆需核对目标分支，并执行 `git submodule update --init --recursive`。源码 ZIP 不包含固定 Core 子模块。见[开发指南](docs/NATIVE_DEVELOPMENT.md)。

<a id="zh-usage"></a>

## 快速开始

1. 打开 App，在设置中选择语言、外观及已有 Python 解释器。
2. 首次操作选择已有启动器目录。“一键检测”只读检查 Guest，要求 FX 已运行；需要时先在 FX 管理中点击“启动 FX”。
3. 在总览点击“启动 HELLDIVERS 2”，原有启动流程自动完成必要检查。核对启动确认及具体配置变更预览；密码仅填写 App 安全输入框。
4. 在游戏性能配置页查看硬件与基准差异，在日志页查看错误详情。检测到进程不代表已经进入主菜单。

<a id="zh-development"></a>

## 兼容性状态

| 证据 | 当前结果 |
| --- | --- |
| Native App | Debug 构建、六页冒烟检查通过；本轮定向检查为 35 项迁移及 9 项推算用例 |
| FX／游戏进程 | 此前记录中的专用 FX 1.9.4 启动已观察到；不代表任意 FX 安装均兼容 |
| 主菜单／可操作飞船 | 2026-11-03 用户明确确认，限定于该记录环境 |
| 当前 GUI SSH／Guest 读取 | 已连接真实后端；最近宿主检查因另一份 FX 正在运行，在连接前拒绝。新入口的成功实测仍待完成 |
| 单人任务／独立 EAC 验收／多人联机 | 分别保持**未验证** |
| 性能 | 只读候选比较，没有实测性能保证，也不自动调优 |

> [!WARNING]
> 发现安装 ≠ 运行就绪 ≠ 游戏进程已启动 ≠ 进入主菜单 ≠ EAC 验证成功 ≠ 多人联机成功。不提供反作弊绕过。

## 常见问题

- **为什么停止／重启或应用按钮禁用？** 尚无经验证的正常退出后端，以及安全推算／写入／恢复边界。App 不强制停止或静默重配 FX。
- **每次都要输入密码吗？** 默认会话内复用。主动选择记住后，经实际验证的 SSH／sudo 凭据分别保存在本 App 新建的 macOS Keychain namespace；自动读取禁止授权弹窗。钥匙串锁定／访问受限时回退安全输入，主动授权访问或 App 身份／签名变化时仍可能出现系统授权。旧脚本钥匙串项目保持不动。
- **自动更新能用了吗？** 已集成 Sparkle 2，但签名 Feed／发行服务尚未配置，更新检查禁用，安装未验证。

<a id="zh-legacy"></a>

## 开发文档与原脚本

- [main](https://github.com/LSJOP/helldivers2-fx-launcher/tree/main)：已整合 Native 成果的主线。
- [feature/macos-native-app](https://github.com/LSJOP/helldivers2-fx-launcher/tree/feature/macos-native-app)：保留 Native 开发历史，后续复用前需安全同步 main。
- [legacy-script](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script)：原脚本归档，保留历史。
- [开发指南](docs/NATIVE_DEVELOPMENT.md) · [迁移证据](docs/FUNCTION_MIGRATION.md) · [性能配置](docs/GAME_PERFORMANCE.md) · [自动更新](docs/NATIVE_UPDATES.md) · [开发规则](AGENTS.md)

<a id="zh-disclaimer"></a>
<a id="zh-license"></a>

## 免责声明与协议

本项目非官方，不宣称获得官方认可，不保证兼容性。HELLDIVERS 2 及相关标识归各权利人所有。项目统一源码许可证**尚未选定**，不应推定均可自由再分发。见[权利与来源说明](THIRD_PARTY_NOTICES.md)，其中保留 Sparkle 的独立许可证和用户提供素材的来源。

开发检查：`python3 native-app/script/check_localization.py` 报告十语言键／格式覆盖和 README 待审范围；`native-app/script/run_checks.sh` 及提交钩子包含此门槛。界面变更必须审查中英文 README 及真实截图。英语截图已在 UX 验证后更新；非英语截图和译文自然度仍需人工审校。尚未配置 CI 工作流。

FX 选择 V2 + 自动选择 V2.1：FX 管理、总览和启动窗口共享并持久化同一个默认 FX。扫描结果中只有一个通过身份和路径验证的 FX 时自动选择；多个 FX 时保留有效默认，否则请用户选择。默认 FX 删除、移动或更新后重新验证。选择后仍显示**启动能力待验证**，不会自动启动游戏。每次启动游戏先重扫默认 FX，再执行原有可执行文件哈希、身份、配置和启动预检；其他构建可以被选中，但仍可能被兼容性检查阻止。FX 应用和辅助脚本／gvproxy 的启动资源目录明确区分：优先从所选应用的有限上级目录或已有资源目录解析，无法解析时才请用户定位一次**启动资源**，不再重复选择 FX 目录。刷新与自动检查不会启动 FX、SSH 或游戏。停止／重启和性能应用／恢复仍不可用。
