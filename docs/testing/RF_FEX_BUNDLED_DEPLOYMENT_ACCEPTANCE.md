# RF 资源内置与部署验收

## 三组件内置 · 2026-11-25

环境分支以 `9084b5ce7aec07860a2ce1aa496b64758e3d36a0` 为开发起点，远端 main 为 `dfe2c18e5fb586b918cf089e1f3900a2e85459aa`。固定版本组合来自 [FX 1.9.12 成功环境审计](../environment/FEX_SUCCESS_ENVIRONMENT_REPORT_FX1912_20261115.md)中的工具映射、归档和实际启动记录。历史镜像保持原状。没有升级或重新编译组件。

| 组件 | 版本和构建 | 本机 Debug 内容 | 字节数 | SHA-256 | 本次真实部署 | 公开分发 |
| --- | --- | --- | ---: | --- | --- | --- |
| RF FEX | `eac-main-20261022-historical` | 41 文件树 | 26,327,173 | `0ddd70d9b19e0a6abac26d9edb442fe43557376670c46d9489890f7eef913cd7`（树指纹） | BLOCKED | 未批准 |
| Proton-JE | `11.0-20261014-3`，`1792806463` | 上游原始 xz 归档 | 348,245,820 | `aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485` | BLOCKED | 未批准 |
| SteamLinuxRuntime_4 | `4.0.20261021.265997`，构建 `26116036`，历史 depot manifest `622183911945836103` | 历史原始 tar 的确定性 xz 封装 | 193,365,028 | `d70d0db92512bd9cc0d200618b780fd8da37cc5cb6c5cad9326df261f20b468d` | BLOCKED | 未批准 |

Runtime 原始 tar 为 717,803,520 字节。解压后的 tar 字节流与原始 SHA-256 `31a43e6e6ff78509eb1cdb762cfff8e9d89fc83c118d5d723bead42b9b18ca5c` 一致。历史 `VERSIONS.txt` 和两种架构的 pressure-vessel 包装器哈希与原审计一致，ELF 架构分别为 AArch64 与 x86-64。Proton-JE 的 Wine 核心为 x86-64，安装清单完整校验了 5,609 个文件和 1,896 条链接；版本和归档哈希与历史成功组合一致。

### 构建、空间与更新

- 最终本机 arm64 Debug 构建位于 `native-app/build/OfflineCoreVerifiedDebug/HD2FXNative.app`。签名、两个归档和 RF 41 文件核验通过。Release 和 CI 同时启用私有开关的实际构建阶段负例被拒绝。无私有开关时，构建门禁也拒绝输出目录中的残留归档。
- 运行组件文件合计 **567,938,021 B**，含 RF 清单的 Deployment 目录为 **567,971,934 B**。App 文件逻辑大小 **614,360,282 B**。最终签名 Debug 的本机测量 DMG **577,415,332 B**，ZIP **574,060,449 B**。相较压缩归档，Proton 和 Runtime 的解压后普通文件分别为 **1,471,447,109 B** 与 **711,197,025 B**，还将增加目录及链接。保留内置压缩归档。
- 隔离宿主夹具使用完整 Proton 归档，禁用下载后运行真实安装脚本耗时 **28.59 s**，通过校验、临时归档清理和恢复。压缩归档与安装树并存采样为 **1,789,312 KiB** 的实际分配空间。Runtime 完整归档的同一 staging 脚本耗时 **8.53 s**，比对完整树指纹通过。未测 Guest 峰值、实际 SFTP 吞吐、断点续传或首次缺失配置总耗时。
- 本机测量 ZIP 已超过签名清单、验证器与更新助手共同的 **536,870,912 B** 上限。保留这一门禁及现有更新协议。正式分发前要另行协调更新端到端上限与内存预算，或将签名 App 更新与核准的组件制品拆分。没有生成正式更新签名或发布文件。

### 本机导入与部署

按已审核归档导入。Runtime 输入是原始 tar，工具重封装并核验固定哈希。RF 继续使用下文的原有导入工具。

```sh
python3 -I -B native-app/script/deployment_archives.py import \
  --catalogue native-app/Resources/deployment-components-v1.json \
  --destination native-app/PrivateResources \
  --proton "$VERIFIED_PROTON_ARCHIVE" --runtime "$VERIFIED_HISTORICAL_RUNTIME_TAR"
```

Xcode 在原本机 Debug 开关之外设置 `HD2_PRIVATE_CORE_DEBUG=YES`。App 两个入口共用现有环境流程。完整的已安装树跳过归档读取。缺失时先校验 App 内置归档，再通过同一认证 SSH/SFTP 通道上传。Proton 复用完整清单及原部署回执，Runtime 复用 RF 事务的安全解压、Steam 注册与实际探针，目标是 `SteamLinuxRuntime_4`，保留原有 ARM64 版本。上传和安装阶段分别显示。有效内置文件安装时不请求上游归档或 Proton 校验文件。现有固定联网来源仅作备用。RF 仍无获批下载包。来源不明或已漂移的已安装树仍由冲突检查保护。

### 许可及实机边界

- Proton 的 [固定发行页](https://github.com/jegglest/proton-je/releases/tag/proton-je-11.0-20261014-3)指向对应 Proton/Wine 来源。归档含许可证，确切完整对应源码、第三方组件和通知义务尚待逐项核准。[Valve Proton 许可说明](https://github.com/ValveSoftware/Proton/blob/proton_11.0/LICENSE)
- [Valve Runtime 固定版本档案](https://repo.steampowered.com/steamrt4/images/4.0.20261021.265997/)包含校验、包清单及源码目录。内置内容来自历史 Steam depot。需补齐该具体归档的来源映射、各包再分发条件及 ARM64 伴随文件的权利依据。RF 的 MIT 基础源码许可已记录。完整二进制与对应源码的映射，以及 Valve 伴随内容的再分发许可仍待核准。
- 真实 FX 1.9.9 独立副本仍有完整运行环境。之前的启动及三组件试构建重试均在 `AuthenticatingSSH` 超时。宿主只读核验确认仍是独立副本、转发端口有 SSH banner，已知主机密钥通过，无认证材料的连接被服务器拒绝。操作还建立过已认证的 App SSH master，核对仍为同一 Guest boot，最终 App 的连接并检测操作返回 `TIMEOUT`。未取得组件缺失基线，未移动或删除现有文件。
- 完整 `run_checks.sh`、109 项 Native Core、29 项集成、161 项部署回归，以及构建签名、十语言和文档检查通过。新增离线 Proton 与 Runtime 的脚本夹具通过。
- 新版真实离线部署、损坏替换、真实回滚、两次重启及持续性均未验收。下文两次重启属于上一轮既有安装。Steam 派发、接单、进程、窗口、主菜单、单人任务、正常退出、反作弊及多人联机均未观察到。


## Dashboard V003 整合

整合前环境分支为 `fdca49a42774a61d273e03a6aa42c40a3f3dd14d`。远端主线 `dfe2c18e5fb586b918cf089e1f3900a2e85459aa` 为 PR #22 的合并提交，已合入现有环境分支历史。合并后当前分支 SHA 以 `git rev-parse HEAD` 为准。

- Dashboard、侧栏导航、主线更新服务及 Update Helper 保留主线文件。截图与对应的来源清单使用主线的同一套证据。
- 首次配置采用主线完成页布局和主题色，保留环境分支的进度、脱敏诊断和认证。FX 实例选择回到总览。
- 十语言各 618 个键。采用基于共同祖先的键级整合，保留新增翻译及主线对旧界面键的移除。
- 保留最新稳定版发布说明和截图，同时保留未发布的环境配置记录。整仓扫描中原有的测试密码样本已改为明确无效的测试占位值。

### 合并后证据

| 项目 | 结果 |
| --- | --- |
| 主线合并 | PASS，双亲合并提交为 `4a67637c1e4e8a68eca70b19c774e49251f6e610` |
| 总览 V003 | PASS，核心视图、导航和设计系统与远端 main 一致。中英深浅与普通、窄窗已复核。多实例的路径区分、设置入口和四卡状态已观察 |
| 高级诊断和滚动条 | PASS，独立只读 App 窗口验证诊断入口。窄窗口六页滚动审计通过 |
| arm64 Debug 与实际 Bundle | PASS，41 文件的路径、大小、模式与 SHA-256 通过，指纹为 `0ddd70d9b19e0a6abac26d9edb442fe43557376670c46d9489890f7eef913cd7` |
| 私有资源门禁 | PASS，Release 和 CI 的执行负例均拒绝私有资源 |
| 功能回归 | PASS，SSH 38、Native Core 107、集成 29、部署事务 161、RF 事务 22、运行探针 15。自动更新、签名、十语言和敏感信息扫描通过 |
| README 截图来源门禁 | PASS，合并后重新采集并复核 12 张双语实际窗口，提交原始截图。首次运行检查因旧截图指纹失败，随后重跑完整门禁 |
| 完整 `run_checks.sh` | PASS，复拍后脚本退出 0 |
| 真实磁盘选择 | PASS，FX 1.9.9 VM 进程打开的副本 inode 为 `3113256`，已观察到正常关机及启动器托管的重新启动。原盘和备份未打开 |
| 真实 SSH | PASS，App 复用已存凭据并进入环境检查。首次直接启动 FX 被网络进程保护拦截，正常关机后由 App 重试成功 |
| 真实 sudo | PASS，App 报告密码已验证、命令完成、配置未改变。首次在前一任务收尾时返回 BUSY，空闲后重试通过 |
| 既有 RF 环境复验（D） | PASS，匹配完整树后完成实际运行探针和最终环境验证，未执行 RF 上传 |
| Proton-JE、Runtime 4、Steam 和启动参数 | PASS，既有环境通过 App 最终验证。Runtime 4 通过 App 管理的 FX 容器探针。本轮未重新安装这些组件 |
| 第一次正常重启 | PASS，boot 从 `d3199b25` 变为 `b0922ad4`，重新连接后通过实际运行探针与配置完整性检查，已装组件保持原样 |
| 第二次正常重启 | PASS，解锁后读取原 App 结果，Guest boot 从 `b0922ad4` 变为 `8fbc8f5f`。App 显示配置完成，FX、Proton-JE、Steam 与启动参数检查通过。VM 文件句柄仍指向独立副本 |
| A 缺失、B 损坏、C 权限、E 中断 | BLOCKED，现有副本的 RF 安装完整，当前启动没有可用于现有恢复事务的安装回执，未执行真实故障注入 |
| G 用户与库路径、H 离线 | NOT_TESTED，未切换真实测试身份或隔离 Guest 网络 |
| F 重复执行 | PASS，第一次重启后再次执行配置并完成校验，未见 RF 重新部署 |
| 游戏启动前置复验 | 首次在 Guest 休眠期间返回 `SSH_HANDSHAKE_INTERRUPTED`，诊断指明凭据提交前中断。唤醒后从总览重试，通过环境复验，在 `StartingSteam` 返回 `GUEST_INSPECTION_FAILED` |
| Steam 启动请求、接受、进程、游戏窗口、主菜单、单人、退出、EAC 与联机 | 尚无成功证据，详见下方复测记录 |
| Release RF 资源和 RF 网络备用 | BLOCKED，公开来源及再分发审批未完成 |

真实副本原先已装有与 Debug 完整清单一致的 RF 树，App 显示指纹 `23b5d17d9bcdd332ce57d2fcbdfece90279106d845b52c84c77bd31bf10fd655`。本轮修订允许受控 Debug Bundle 核对这个精确匹配并进入运行探针，未批准的其他树仍走原有确认。修订后的 arm64 Debug 源码为 `564d31274056a02dfdad5abfd4ad10a055625e97`。

2026-11-24 第一次游戏尝试使用首次配置完成页按钮进入总览的启动流程。当时总览会保留设置结果并隐藏主启动按钮。修订后用真实 arm64 Debug App 重新运行配置，确认既有环境通过，点击总览后观察到 `dashboard.launch` 和 `dashboard.inspect`，并实际点击前者发起游戏。自动化覆盖配置进行中、配置成功和游戏启动完成三种状态。Guest 状态脚本修复了无可用 Steam 登录记录时生成无效 JSON 的确定性缺陷，并用实际脚本回归覆盖；早先实机报错未包含原始状态内容，无法单凭错误码确认其具体输入。

第一版修订的 App 源码为 `74295b9d2058464b3c9d1a8ecc19b62d3c9d9195`。完整 `run_checks.sh` 退出 0，Native Core 108 项通过。本机 Debug App 重新校验 41 文件，Bundle 指纹仍为 `0ddd70d9b19e0a6abac26d9edb442fe43557376670c46d9489890f7eef913cd7`。

新版在等待 Steam 登录时，通过绑定到同一 Guest boot 的既有 App SSH 会话执行只读诊断。Steam 服务为 active，日志末尾可提取 `Logged On`。原 grep 将日志判为二进制，退出前不返回匹配标签。修订将有界尾部按文本读取，仅提取已知的登录状态标签。回归执行实际状态脚本，覆盖无日志及包含二进制字节两种输入。

Steam 状态修订的 App 源码为 `cd316819177fb06a0ab9a8d34219a4dc5d5e3860`。arm64 Debug 重建、签名、本机 41 文件及完整 `run_checks.sh` 通过，Native Core 109 项通过。已用真实总览启动按钮发起启动复测，宿主随后锁屏，暂无法继续观察交互结果。恢复观察前，Steam 派发、接单、游戏进程、窗口、主菜单、单人、正常退出、EAC 和联机均记为 NOT_TESTED。

以下原有记录属于合并前构建。合并后验收另列。

开发分支基线为 `79095bf9819bc1321d31963585574b02a39d8d15`。历史镜像和审计报告保留原样。

| 范围 | 复用与变更 |
| --- | --- |
| 资源输入 | 12 个历史 stage 文件、28 个伴随文件和 1 个脱敏 wrapper。详见[逐项清单](../../native-app/Resources/rf-fex-debug-manifest-v1.json)。 |
| 构建 | 复用 Xcode 资源复制阶段，增加本机显式开关及复制前后核验。CI 和 Release 拒绝私有 payload。 |
| 首次配置 | 复用 `first_run_fex_repair`、身份绑定的 SSH/SFTP、持久化目录、事务收据、回滚及运行探针。已有 Debug 外部回放继续作为开发工具。 |
| Runtime 与 Proton | 复用 Runtime 4 已固定的 Valve 下载、缓存及验证，以及后续 Proton-JE 配置。保留 SteamLinuxRuntime_4-arm64。 |
| 分发 | Release Bundle 审批哈希清单当前为空。公开 RF 下载 URL 与制品哈希尚无批准记录。 |

在仓库根目录执行本地导入。将 `$RF_EVIDENCE_DIR` 指向已审核的历史证据目录。

```sh
python3 -I -B native-app/script/rf_fex_bundle.py import \
  --manifest native-app/Resources/rf-fex-debug-manifest-v1.json \
  --source-root "$RF_EVIDENCE_DIR" \
  --destination native-app/PrivateResources/Deployment/RF-FEX
```

使用独立构建输出目录，以 Xcode arm64 Debug 配置和 `HD2_PRIVATE_RF_DEBUG=YES HD2_UPDATE_ENABLED=NO HD2_UPDATE_DISTRIBUTION_READY=NO` 构建。App 运行时从 `Contents/Resources/Deployment/RF-FEX` 读取，并验证编译时固定的清单哈希。带私有资源的 App 仅本机使用。

历史 wrapper 从 6,536 字节转为 6,498 字节，移除环境打印。脱敏后 SHA-256 为 `e65da61350150ca527da3da9da5e5ecc1bf97ac9807d2e6ac22a09ffcf6f2045`。保留 ARM64 stock GDB reader。重复的 ThunksDB 使用同哈希的伴随资源副本。运行生成的 Python 缓存以及 stage 专用 GDB reader 均排除。

完整 Bundle 的 41 条文件路径、大小、模式和 SHA-256 见逐项清单。实际 Debug Bundle 目录的校验指纹为 `0ddd70d9b19e0a6abac26d9edb442fe43557376670c46d9489890f7eef913cd7`。部署保持空字符串 RootFS 注册，并由现有探针验证实际运行。

FEX 基础源码有 MIT 许可证记录。历史二进制的完整源码与补丁映射，以及 stock/Valve wrapper 和伴随库的再分发依据仍待确认。待审批项见环境组件清单。

| 项目 | 结果 |
| --- | --- |
| arm64 Debug Bundle 和 41 文件检验 | PASS |
| 真实 App 冷启动与打开首次配置页 | PASS，独立本机 App 数据目录 |
| 私有 payload 在 Release 和 CI 的构建拒绝 | PASS，执行 Xcode 资源阶段的两个负例 |
| FX 1.9.9 原盘、离线备份及独立测试副本 | PASS，独立 inode 且完整逐字节比较一致 |
| 缺失自动进入修复入口 | PASS，静态检查 |
| 损坏替换、权限位、事务和 RootFS | PASS，隔离文件系统测试 |
| 真实 SSH/SFTP、App 配置 A–H、两次重启 | NOT_TESTED |
| Steam 启动请求、游戏进程、游戏窗口、主菜单、单人、多人 | NOT_TESTED |
| Release 制品与 RF 网络备用 | BLOCKED，等待制品及完整再分发审核 |

实际构建使用干净源码 `933872929de7019b88213f573854490dfc8a9009`。arm64 主可执行文件 SHA-256 为 `b057806cea25297fa44b2004178267b81de2bb8d0dd094d5cb4543973c5319be`，Debug dylib 为 `3610ffd1b9db423a33a50fc974b9784910f0a4802263a5197bc6111610182003`。实际 Bundle 的两项更新标记均为 `NO`。

资源树与清单共 42 个文件通过敏感信息扫描。新增及修改的 Git 文件也通过暂存扫描。全仓已跟踪文件扫描在既有 `PersistentCredentialChecks.swift` 中报告一项测试凭据模式命中，该文件本次无改动。

FX 1.9.9 偏好指向 144,286,154,752 字节的测试原盘。原盘无打开句柄时创建备份，与备份完整比较后再次确认无打开句柄，再制作独立副本。副本与备份完整比较通过。副本来自已配置环境，后续缺失、损坏与权限场景应记录为副本上的回归测试。待将 FX 明确绑定到副本并完成 App 内认证后开始 Guest 测试。
