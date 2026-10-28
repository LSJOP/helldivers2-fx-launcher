# 已测试环境与兼容性 / Tested environments and compatibility

[README](../README.md) · [依赖 / Dependencies](DEPENDENCIES.md)

## 简体中文

更新日期：2026-10-29。表中“历史观察”“用户反馈”“离线检查”“未验证”是不同证据等级，均不能自动等同于当前下载包的正式支持承诺。没有发布最低硬件／系统支持清单。

### 已有证据

| 环境／范围 | 结果与证据类型 | 不能据此声称 |
| --- | --- | --- |
| M4 Pro、24 GiB 统一内存、macOS 27.2；FX 1.9.4 专用副本、补丁 FEX、Proton-JE `11.0-20261014-3` | 2026-10-28 私有本地记录保存了游戏进程、组件版本及当时 EAC 检查结果；属于历史单机观察。公开文档仅摘录必要版本，不附原始记录。 | 普通 FX 全新安装可用；其他机器／系统可用；当前源码已在干净环境重现。 |
| 同一专用环境的联机 | 用户报告约三小时成功匹配／游玩；记录包含会后状态采集，未连续监测整段会话。 | 三小时无掉线、同一进程连续三小时、所有网络可用或长期稳定。 |
| 发布入口、双语提示、本地组件检查 | 2026-10-29 在 macOS 完成 219 项隔离检查，覆盖受限模式、系统语言初始化、手动设置、原有回归及 86×29 / 88×27 布局；未运行游戏。 | 安装成功、Guest 环境正确、EAC 成功或联机可用。 |
| UI 与十种语言 | 有离线布局／输入回归记录；本次 README 图片由当前绘制代码离线生成，状态均未检查。 | 母语审核全部完成、所有终端字体表现一致或实时连接已验证。 |
| Python 3.9.6 | 已用于本地入口检查；启动器使用 Python 标准库。 | 所有更新版本或所有 macOS 安装方式均已验证。 |

### 尚未验证或尚未完成

| 项目 | 当前状态 |
| --- | --- |
| 普通 FX 全新安装 → 自动准备组件 → 启动游戏 | **未完成 / 未验证** |
| 其他 M 系列芯片、其他内存容量 | **未验证**；M4 Pro 的历史记录不扩展为整个 Apple Silicon 支持。 |
| Intel Mac | **未验证**；本地预检查以 Apple Silicon 为目标。 |
| 其他 macOS 版本与最低 macOS 版本 | **未验证 / 未确定** |
| 普通网络直连、不同代理软件／端口 | **通用适配未完成 / 未验证** |
| 不同游戏、Steam、FX、FEX、Proton 更新后的组合 | **未验证**；需逐版本重测。 |
| 所有模式的 EAC 与跨平台联机 | **未验证**；不能以进程存在或探测成功替代。 |
| `.app`、签名／公证安装包、自动升级 | **未实现** |

### 如何补充一条兼容性记录

提供日期、源码提交／版本、芯片与内存档位、macOS、FX/FEX/Proton 版本，以及分别记录的安装、启动、EAC 和联机结果。说明是否全新用户环境、验证步骤与观察时长。网络只记录“直连／系统 TUN／自定义代理”等类别，不提交公网 IP、节点名称、账号、订阅或原始日志。未观察到的项目写“未验证”。

本表的硬件和历史结果来自本地已存在的记录，未在本次文档工作中重复启动游戏。内部维护记录不随玩家下载分发。

## English

Updated 2026-10-29. Historical observation, user reports, offline checks and unverified combinations are distinct evidence levels. None is a blanket support promise for the current download. No minimum supported hardware or macOS version has been established.

| Environment / scope | Evidence | Limitation |
| --- | --- | --- |
| M4 Pro, 24 GiB, macOS 27.2; dedicated FX 1.9.4, patched FEX, Proton-JE `11.0-20261014-3` | Historical local record dated 2026-10-28 includes game-process, component and contemporaneous EAC observations. | No clean-install validation of the public source or ordinary FX distribution. |
| Multiplayer in that dedicated environment | User reported roughly three hours of successful matching/play; capture includes post-session state. | No continuous monitoring, zero-disconnect claim or universal network support. |
| Public shortcuts and local checks | 219 isolated checks on macOS dated 2026-10-29, covering limited mode, native language initialization, manual settings, existing regressions and 86×29 / 88×27 layouts. | No real game, Guest installation or multiplayer verification. |
| UI / ten languages | Offline layout/input regression records; current preview images show unchecked synthetic status. | No complete native-language review or live connectivity proof. |
| Python 3.9.6 | Used for local entry validation. | Other versions/installations remain unverified. |

Other chips, memory sizes, Intel Macs, macOS versions, direct/custom networking and updated runtime/game combinations are unverified. Automatic full setup, a desktop `.app`, signed/notarized installers and automatic updating are unfinished or absent. Runtime presence and HTTPS/STUN results do not prove EAC or multiplayer.

To add evidence, report date, source revision, chip/memory category, OS and exact runtime versions, then separate installation, startup, EAC and multiplayer outcomes. State whether the environment was fresh, what was observed and for how long. Share network categories only; omit addresses, node names, subscriptions, account details and raw logs. Mark unobserved outcomes unverified. No game was relaunched for this documentation update.

Python/Node 安装路径及功能检测已做本地只读验证；Homebrew 安装分支使用临时模拟程序测试。尚未在干净 Mac 真实安装，本项目版本号不代表该安装验证已经完成。

Python/Node paths and capabilities were checked locally without installation; Homebrew branches used temporary mock tools. Fresh-Mac real installation remains unverified.
