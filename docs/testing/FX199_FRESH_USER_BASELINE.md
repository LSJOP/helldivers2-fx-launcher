# FX 1.9.9 首次配置基线与验收

核对日期为 2026-11-27（Asia/Shanghai）。本机使用 GitHub 正式 v1.0.7（2026112702）实测。恢复依据为 [FX 1.9.9 新镜像报告](../environment/FEX_BASELINE_REPORT_20261115.md)、[FX 1.9.12 历史环境报告](../environment/FEX_SUCCESS_ENVIRONMENT_REPORT_FX1912_20261115.md)、本地审计目录中的 `FX_PREVIOUS_OPERATIONS_AUDIT.md`、`STEAMOS_ENVIRONMENT_TRACE_20261104.zh-CN.md`，以及 Guest 部署回执、配置备份和历史操作记录。

## 新用户基线

| 环境 | 结果 | 证据 |
| --- | --- | --- |
| FX 1.9.12 历史成功环境 | 只读参考 | 沿用历史报告，原盘留在原位。 |
| FX 1.9.9 `FX199_FRESH_USER_BASELINE` | PASS（功能等效） | 独立副本撤回后续部署，经正常关机后进行离线核对，母本设为只读并加 macOS 用户不可变标记。 |
| FX 1.9.9 恢复演练 | PASS（两次） | 恢复副本具备独立 inode，启动前完整 SHA-256 与母本一致。正式 App 已从第一份副本启动并连接到所选 Guest。 |

`FX199-RF-acceptance.ARpYR0/backup.img` 采用 APFS 写时复制，源与该初始工作副本完整 SHA-256 为 `bdfe63971dccf533264a251f27938a69c3675cb43ba3f5c6d64f98ee8df62a02`。只在工作副本中变更 Guest。先核验 RF 安装树与历史备份指纹，沿部署回执恢复原状态，再将完整校验过的 Proton-JE 移出 Steam 工具目录。通过 Steam 客户端卸载 4183110，Steam 日志记录 06:34:01 `finished uninstall (No Error)`。启动参数恢复为空，兼容工具恢复为最早匹配回执中的 `proton_11-arm64`。确认系统 FEX、Steam 原版 FEX、ARM64 Proton、4185400 Runtime、Steam 登录和游戏可执行文件均保留。

母本位于本机外置卷的 `/Volumes/Thunderbolt2TB/FX199_FRESH_USER_BASELINE/master.img`，完整 SHA-256 为 `62504434271bde46c3ee4b361b0aebc3c97224226f50652c5668e49f34f4de1a`。同目录保存镜像来源、前后清单、卸载事件、恢复结果与 `restore-working-copy.sh`。正常关闭 FX 后，从该目录运行 `./restore-working-copy.sh attempt-N.img`，确认 SHA-256 后将 FX 1.9.9 测试实例绑定到 `runs/attempt-N.img`。每轮使用新的 App 数据目录和首次配置状态。测试实例使用本机 2223 SSH 端点。

与 11 月 15 日观测环境相比，基线保留后来由 Steam 安装的原版 FEX depot（3127680）、明确的 ARM64 Proton 映射、游戏 prefix、Steam 历史及缓存、Guest 私有回退留档。回退留档处于组件扫描路径之外。保留备份中的网络与性能状态，历史报告缺少足以定向撤回这些设置的变更前记录。候选重启后观测到 Guest 的 `all`、`default`、`eth0` 与 `lo` IPv6 disable 值均为 0。现有证据支持三个目标组件在首次配置前缺失，未能证明与历史任一时刻逐字节相同。

## 正式 v1.0.7 实机

首页操作启动了绑定恢复副本的 FX，完成真实 SSH 与 Guest 识别。06:38:59 调用 Steam 安装 4183110，出现 Steam 的兼容性未知确认框，首次配置无法自行继续。另作诊断时通过已认证 Steam 客户端排队，官方 Runtime 下载 250,976,848 字节后成功安装，Build `26116036`、版本 `4.0.20261021.265997`，Steam depot `4183111`，manifest `622183911945836103`。随后 App 内置 RF FEX 事务完成并写入已验证回执，Guest 树指纹为 `518185cf0713a01224d38c04897897547d8ec5e80f04426a45662b5bdd64e09f`。

RF 部署后的观察探针返回 `STEAM_RUNTIME_INCOMPATIBLE`。实机复现表明 Swift JSON 编码的 `\/` 嵌入 Python 字符串常量后保留了反斜杠，导致探针检查错误的路径。对相同数据执行 JSON 解码后，安装路径、运行库检查和 RF 容器探针均通过。修复用身份核验后的 Steam 客户端直接排队缺失组件，并通过 Base64 封装 JSON，将原样路径传给 Guest。保持完整的 Steam 安装、磁盘内容和 RF 容器检查。修复源码在现有 `fix/first-run-ssh-access` 工作分支的 `c686f7b`。

| 项目 | v1.0.7 实机状态 |
| --- | --- |
| 新用户基线恢复与三个组件同时缺失 | PASS |
| 首页自动排队并安装官方 Runtime | FAIL（Steam 确认框） |
| 内置 RF FEX | 诊断续跑的实际事务通过，随后的 App 复验失败 |
| 内置 Proton-JE、首次配置完成、重复配置与重启持久化 | 未完成 |
| 首页一键启动游戏、游戏窗口、主菜单、单人任务、正常反作弊与多人 | 未验证 |
| 正式 v1.0.4 → v1.0.7 全量自动升级 | PASS |
| 正式 v1.0.5、v1.0.6 在本机启动 | FAIL（Sparkle 库验证） |
| 正式 v1.0.7 → v1.0.8 的真实组件增量升级 | PASS（见下文） |

## v1.0.8 候选实机

候选 arm64 build `2026112703`，源码 `c686f7b55aa59380f896e322cd9470e600ff644b`。用第二份完整 SHA-256 校验过的副本和独立 App 数据目录，在首次配置页点击自动配置。06:51:22 Steam 自行排队，06:51:55 安装完成（33 秒），下载计数 250.98 MB。版本 `4.0.20261021.265997`，Build `26116036`，depot/manifest 与 v1.0.7 的诊断下载一致。没有点击 Steam 确认框或执行手动安装。RF 事务与复验通过，内置 Proton-JE 上传、安装及复验用时 62 秒。App 实际验证 sudo，保存启动项，重启 Guest，重新认证后应用 Proton-JE 工具映射。06:57:07 App 显示配置完成，全程 369 秒。

候选内置的 RF FEX、Proton-JE 自动部署与首次配置结果为 PASS。原始 ARM64 组件保留，重启后 Steam 识别 Proton-JE 和对 4183110 的依赖。记录保存在基线目录的 `candidate-first-run-app-events.txt` 与 `candidate-first-run-completed.png`。修复相关 Native Core 119 项、RF 探针 16 项和 RF 部署事务 19 项通过。正式包、首页首次配置、独立重复运行、游戏及真实增量升级另行验收。
候选首页 06:58:10 发出 Steam 启动请求，Steam 完成其运行依赖安装后启动游戏。观察到 `helldivers2.exe` 的底层可执行文件是 App 部署的 RF FEX，EAC Bootstrapper 返回 `301: Easy Anti-Cheat successfully loaded in-game`。游戏显示显卡驱动版本未知的提示，选择游戏内继续后，第一次运行在主菜单前发生 `0xc0000005` 读访问异常，故障地址落在 `helldivers2.exe`。保留本地 minidump 摘要，无外发崩溃报告。按原配置重复从首页启动，正常通过游戏图形提示和游戏初始选项后显示标题界面并进入舰桥。Steam 只下载了常规语言包（250.32 MB），未重装游戏或调整反作弊。


## 正式 v1.0.8 发布与增量更新

[v1.0.8 Stable / Latest](https://github.com/LSJOP/helldivers2-fx-launcher/releases/tag/v1.0.8) 于 2026-11-27 07:05:40（Asia/Shanghai）发布。arm64 build `2026112703`，发布源码 `c686f7b55aa59380f896e322cd9470e600ff644b`。App 415.58 MB，DMG 382.53 MB，全量 ZIP 379.11 MB，App Core 23.95 MB。签名清单固定复用 v1.0.7 上已发布的 RF FEX（6.84 MB）及 Proton-JE（348.32 MB）。验证内容包括严格签名、Ed25519、完整目标树、只读 DMG、GitHub 制品摘要和发布工作流。

正式 v1.0.7 的独立已签名安装通过实际设置页联网发现 v1.0.8。点击更新后，仅观察到 23,953,205 字节的 Core ZIP，生成完整签名 App 交给 Update Helper，未出现全量 ZIP 请求或组件 ZIP 文件。07:06:50 启动替换事务，07:06:58 新 App 确认启动。重新核对正式构建号、严格签名和主程序字节一致。动态证据为基线目录下 `official-v107-v108-incremental-cache.txt` 与 `official-v107-v108-helper-journal.txt`。该路径为 PASS。

## 正式 v1.0.8 首次配置

2026-11-27 11:45:43–11:51:55（Asia/Shanghai），用经正式增量更新安装的 v1.0.8 和另一次完整 SHA-256 还原的独立副本，从首次配置页启动。App 使用隔离的数据目录和已选的 FX 1.9.9 测试实例。Guest 开始时没有 RF、Proton-JE 或可用的独立 Runtime。Steam 11:46:09 开始下载，11:46:37 完成，下载计数 250.98 MB，Build `26116036`、版本 `4.0.20261021.265997`。内置 RF FEX 安装及实机容器复验通过。内置 Proton-JE `11.0-20261014-3` 事务完成（61 秒），App 自动重启 Guest、重新验证 SSH，并持久化游戏启动参数和兼容工具映射。完整首次配置和重启后复验为 PASS（372 秒），无额外部署确认。

完整母本保留原始 ARM64 Proton。该次运行的 Steam 日志显示客户端先独立更新自己的 ARM64 Proton（4628740，Build `26871091`，`proton-11.0-3-arm64`），之后才安装独立 Runtime。母本不受影响。系统 FEX、4185400 Runtime、游戏可执行文件在运行前后保持对应指纹或已核对的构建号。证据在保护基线目录的 `official-v108-firstrun-app-events.txt`、`official-v108-firstrun-receipts.txt`、`official-v108-first-run-completed.png` 和 `official-v108-stock-proton-steam-update.txt`。

11:52 正常关闭 Guest 和 App，然后使用同一副本重启。正式 App 重新运行首次配置，31 秒完成，配置阶段为 0 秒。部署回执 SHA-256 集合完全一致，无新增部署事务。Guest boot ID 再次变化，三个组件仍在，同一份启动参数和 Steam 映射被复用。证据为 `official-v108-repeat-after-shutdown-app-events.txt`、`official-v108-repeat-after-shutdown-guest.txt` 和重复配置截图。该路径为 PASS。

## 正式 v1.0.8 首页一键配置并启动

用另一份完整 SHA-256 校验过的副本和全新的 App 数据目录，从中文首页点一次启动。2026-11-27 11:54:37–12:02:57（Asia/Shanghai），500 秒内完成缺失组件自动安装、Guest 重启、设置复验、Steam 启动请求及进程检测。Steam 从 11:55:05 至 11:55:29 下载并安装 4183110（250.98 MB，版本 `4.0.20261021.265997`、Build `26116036`）。App 自动部署内置 RF 和 Proton-JE，未使用额外审批、手动组件安装或资源目录选择。

已独立确认游戏进程的底层可执行文件为受管理的 RF FEX，实际 X11 窗口属于 553850。EAC 正常从其服务下载、初始化模块，并返回 `301: Easy Anti-Cheat successfully loaded in-game`。在游戏自带的显卡版本提示中选择继续后，正式版一次进入可见标题、主菜单及舰桥。全天的正式首页测试中，Steam 另下载 240.10 MB 的游戏着色器缓存。正式游戏 Build 和 EXE 哈希保持一致。App 的 500 秒指标截至真实进程检测，实际窗口与界面由独立证据确认。实机使用系统内既有的测试 Guest 认证，App 数据隔离直接用于限定测试副本与收集证据。

日志和截图在基线目录的 `official-v108-dashboard-app-events.txt`、`official-v108-dashboard-game-events.txt`、`official-v108-dashboard-game-main-title.png`、`official-v108-dashboard-game-main-menu.png`、`official-v108-dashboard-game-ship.png`。在测试副本的游戏设置用正常界面绑定缺失的前进键 W，完成舰桥移动。选择已安装的英文语音、中文界面，拒绝可选游戏数据收集，并将麦克风设为按键说话。

单人实机测试使用临时仅限邀请的匹配设置。难度 1 城市任务正常进入、空投并落地，保持单人队伍，验证角色移动、镜头操作及从游戏菜单独自返回飞船。多人复验将匹配设置和难度还原为公开、9 级。公开快速匹配进入三名其他玩家的真实小队，并加入他们进行中的任务。已核对四人 HUD、实际落地、角色移动与任务进度实时更新。两次运行验证了进入和操作任务，未进行完整结算。证据为 `official-v108-single-player-in-mission.png` 与 `official-v108-multiplayer-landed.png`、`official-v108-multiplayer-movement.png`，本地截图包含游戏内显示名。

12:32:06 从游戏菜单正常退出，Steam 记录游戏进程移除。12:32:36 再次点击正式 App 的启动按钮，Steam 创建了新的游戏进程和窗口，EAC 于 12:33:50 再次报告 301 正常加载。复用 RF、Proton-JE、Runtime 4 和 Steam 配置。证据为 `official-v108-game-exit.txt`、`official-v108-game-relaunch-events.txt`。

| 正式版验收 | 结果 |
| --- | --- |
| 三目标缺失时，首次配置页及首页自动部署 | PASS |
| 重复配置、Guest 重启与 App 重开后的复用 | PASS |
| 首页发送 Steam 请求、游戏进程、窗口、主菜单与舰桥 | PASS |
| 隔离单人任务与公开四人任务的进入和实际操作 | PASS |
| EAC 正常初始化及联机 | PASS |
| 游戏菜单正常退出、首页再次启动和窗口观察 | PASS |
| Mac 整机重启、逐组件独立缺失和环境故障矩阵 | NOT_TESTED，本次实机范围为三目标全缺、重用与游戏路径 |

## 发布与主机验收

[v1.0.7 Stable / Latest](https://github.com/LSJOP/helldivers2-fx-launcher/releases/tag/v1.0.7) 发布于 2026-11-27 01:08（Asia/Shanghai），arm64 build `2026112702`，源码 `55f5c70db42269c7eca7b7c85a5b7a4b4b6282f5`。GitHub 上 13 项资产的大小和 SHA-256 与本地一致，包括 Proton-JE 对应源码。DMG 以只读方式挂载，内部 App 通过严格 ad-hoc 签名检查。下表为十进制 MB。

| 产物 | 大小 |
| --- | ---: |
| App | 415.57 MB |
| DMG | 382.52 MB |
| 全量 ZIP | 379.11 MB |
| App Core | 23.95 MB |
| RF FEX 增量模块 | 6.84 MB |
| Proton-JE 增量模块 | 348.32 MB |

开发和产物检查为 PASS。包括 arm64 Debug / Release、部署隔离回归 164 项、更新服务 62 项、RF 探针 16 项和事务 19 项、Proton 事务 20 项、十语言各 627 项、真实中英文首次配置窗口、Schema 2 与 Schema 3 Ed25519 签名、解压预检、实际签名模块组装及完整 App 签名。合法 RF 模块在 macOS 临时目录的路径归一问题已修复。重复组装时原样复用匹配的两个模块。旧正式包缺少模块时选择全量备用。既有四组件协议仍由解析器接受。

本机用 GitHub v1.0.4 原始签名包，在独立安装路径通过 App 更新按钮检测并下载 v1.0.7。Update Helper 替换 App、自动重启并写入 `confirmed` 回执。安装后重验严格签名，主程序与正式构建逐字节一致。该路径下载全量 ZIP。v1.0.5 和 v1.0.6 的原始 GitHub ZIP 均在本机启动时复现 dyld 拒绝映射 Sparkle。崩溃报告的命名空间为 DYLD，两版进程与库 Team ID 不匹配。v1.0.7 正式主程序为 `ad-hoc` 签名，未带触发旧版故障的 hardened runtime 标记。保留两版历史产物，无法打开旧版时可用 v1.0.7 DMG。

此次 v1.0.7 实机直接使用上述升级后的已签名安装，新进程成功打开窗口并操作 Guest。此结果覆盖旧版 dyld/Sparkle 映射故障的实际启动路径。随后已完成 v1.0.7 → v1.0.8 的组件级端到端升级。
