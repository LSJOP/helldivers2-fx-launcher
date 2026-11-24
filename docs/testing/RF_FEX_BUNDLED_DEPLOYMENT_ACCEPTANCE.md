# RF 资源内置与部署验收

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
