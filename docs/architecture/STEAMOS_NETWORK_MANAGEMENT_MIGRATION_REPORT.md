# HD2FXNATIVE — STEAMOS NETWORK MIGRATION

日期：2026-11-04（Asia/Shanghai）。实现/构建提交：`104beaaf2701bedea7fb3f27707f5e853f98fcd1`；候选版本0.1.0 / build 2026110404 / Native Core 1.2.0。本报告中的PASS必须按“实现/隔离/实机”范围解读。

## 1. 交付结论与 Git

**实现与候选交付 PASS；真实 Guest 网络/写入与游戏验收尚未完成，整体 PARTIAL。** IPv6已从启动链解耦；环境页提供独立运行时开关、完整接口快照及恢复；四项网络诊断为真实探测代码，无静态成功占位、无Python Bridge。

在统一PR开发线之外建立独立工作区 `/Volumes/Thunderbolt2TB/HD2-Native-network-20261104`，本地分支 `feature/steamos-network-20261104`。开始时原开发目录有未提交的历史调查文档，Memory-Only工作区另有正在开发的实现；原件均未覆盖。先冻结副本供隔离工作使用，待其提交后整合 `ebbc911`，继而整合文档提交 `b7c08fb`；保留UI精简、1188d59引用修复、身份验证与全部既有历史。中间stash保留，不清理其他分支或worktree。

目标远端分支：`feature/full-swift-native-migration`；[PR #3](https://github.com/LSJOP/helldivers2-fx-launcher/pull/3)保持OPEN，不合并main。实现提交已正常推送，未force-push。报告另作文档检查点，因此最终Git HEAD可能是构建提交之后的文档提交；候选内完整BuildMetadata始终绑定上面的干净构建提交。

## 2. 原始 Python 诊断实现与语义

原目录 P：`/Volumes/Thunderbolt2TB/绝地潜兵脚本/HD2-StonkGuy-Fork-20261024`。本轮直接读取原代码，而非根据四个标签猜功能。

| 项目 | 原实现 | 实际含义与前提 | 新实现与差异 |
| --- | --- | --- | --- |
| VM | `launcher-20261026/status_monitor.py/snapshot`，GUEST_STATUS | 复用已有SSH master，读取Steam登录线索与游戏进程；测SSH请求往返。不是VM外网ping，不会认证/启动FX | NetworkDiagnosticsService的身份绑定Guest SSH往返；Guest无可信会话则PAUSED |
| Steam TLS | 同文件 `steam_latency` | Host本机7890代理CONNECT至store.steampowered.com:443，使用默认CA/SNI验证真实TLS；原总上限1.5s；仅明确无游戏且代理端口就绪时执行 | Swift Core调用系统curl，禁止curl配置和环境代理干扰，经同一Host代理，验证TLS后HEAD；连接2s、总3s、进程5s。计时不是原函数完全相同的握手测时 |
| PlayFab | `goal-dxmt-20261026/start-hd2.py/PLAYFAB_PROBE`、monitor_playfab | Guest对title.playfabapi.com:443分别直连和经192.168.127.254:7890 CONNECT；DNS与证书验证，无账户数据，不要求Steam登录 | Guest固定curl指令，分别记录两条路由；TLS可达不代表登录或联机 |
| UDP | 同文件 UDP_MONITOR、monitor_udp；status_monitor.latest_launch_probe | Guest对stun.cloudflare.com:3478与stun.l.google.com:19302各两次Binding Request，随机事务ID/cookie/type；单次1.5s；另取UDP计数差、ss游戏socket数量、同目标抖动；额外3s采样窗 | Swift生成请求并验证响应，Guest bash UDP传输；单次timeout2s、SSH上限5s，保留4次和3s采样窗；更严格验证报文长度。无所需工具标UNSUPPORTED，不安装工具 |

UDP新测时包含SSH和身份复核开销，不能与旧Guest内部RTT直接比较。连接式UDP套接字限制响应对端；不输出映射IP、账号或数据包。至少2次有效响应可标检查PASS，同时显示n/4；1次为UNVERIFIED，不能称完整UDP路径正常。原进度条的“done>=2”和页脚全样本绿色是两种不同语义，已在文档明确区分。

原页脚 `ui2.py`：`—`是未采样/无可信结果，不是失败；`暂停`是未满足“游戏明确未运行且代理可用”的自动TLS条件，不是用户按了暂停按钮；ready表示该探测完成，error表示该次错误，timeout表示等待到期。PlayFab/UDP页脚可能显示历史launch_probe统计，只在游戏运行时读取，并非每次刷新都重新探测。原post-launch检查异常不会阻断游戏启动。

新状态保留NOT_TESTED/RUNNING/PASS/FAIL/PAUSED/TIMEOUT/UNSUPPORTED，增加CANCELLED和UNVERIFIED。暂停/未检测不显示失败；超时不证明网络不可用；TLS/STUN不证明NAT类型、P2P、菜单、EAC或多人联机。诊断现为显式操作；若用户启动游戏，诊断可取消并让出串行任务队列，诊断结果不是启动门槛。

完整功能矩阵：[PYTHON_TO_SWIFT_FEATURE_PARITY_AUDIT.md](../PYTHON_TO_SWIFT_FEATURE_PARITY_AUDIT.md)。逐项列出FX、实例选择、SSH/sudo/身份、代理、VM/TLS/PlayFab/UDP、哈希、启动项、Steam/游戏、观察、日志、备份恢复、CPU/内存/Vulkan、更新与十语言等；PARTIAL没有冒充全部迁移。优先遗漏为安全启动项编辑、Guest代理完整配置、历史诊断导入、全新VM依赖准备。终端装饰与危险旧实验恢复入口不迁为Native自动功能。

## 3. IPv6 启动解耦与独立设置

旧链：`NativeCoreService.launchGame → CheckingCompatibility → LaunchService.ensureIPv4 → GuestPrivilegedExecutor → /proc写入`。

新链：`launchGame → 只读兼容/身份/哈希/代理/启动项检查 → IPv6可选状态事件 → StartingSteam → 正常受保护启动链`。旧ensureIPv4及旧Settings恢复分发已移除。Guest身份判断不再要求ipv6_ok=true；boot/marker/Host签名与进程/网络/SSH端点身份仍保留。没有删掉其他兼容性或反作弊检查。

IPv6 UI位置为 **运行环境 → SteamOS 网络设置**，不在性能页、凭据页或启动弹窗。启动凭据表单不再提供sudo字段；独立sudo验证保留。设置页仅保留SSH/sudo会话凭据管理，不管理IPv6。

| 控制项 | 读取路径 | 语义 |
| --- | --- | --- |
| all | `/proc/sys/net/ipv6/conf/all/disable_ipv6` | 写入可能级联影响现有接口；单独读取不能判断全局IPv6连接 |
| default | `/proc/sys/net/ipv6/conf/default/disable_ipv6` | 新接口的默认控制值 |
| eth0 | `/proc/sys/net/ipv6/conf/eth0/disable_ipv6` | Guest主要网卡控制 |
| lo | `/proc/sys/net/ipv6/conf/lo/disable_ipv6` | 回环接口控制 |

0允许、1禁用。四项一致也不证明地址、路由、DNS或端到端IPv6可用；其他接口另列详情。实现枚举全部接口；未知/混合不自动修复，缺项/异常值禁止写入。只改运行态，不写sysctl.d，不承诺重启永久生效。本轮没有可用可信Guest会话，因此未重新取得实机当前值；此前早晨0/0/0/0的历史样本不冒充17时后的现状。

生产位置：`Core/SteamOSNetworkService.swift`（绑定、全接口读取、预览、收据、应用/恢复），`Core/LaunchService.swift/GuestPrivilegedExecutor.networkIPv6`（固定特权脚本），`Views/EnvironmentView.swift/SteamOSNetworkPanel`（开关、详情、确认、恢复及诊断），`Stores/AppState.swift`（单一状态与任务管理）。

写入流程：重新验证FX/Guest → 实读全部接口 → 生成before/after精确计划 → 用户确认 → 在该次SSH调用内用stdin认证sudo → 固定root命令再次核对boot、接口集合、全部原值及游戏空闲 → 写all/default和接口值（保留其他接口原值）→ 全量读回。已正确配置则不认证、不写入。混合状态可主动选择开启或关闭。

原值、目标、稳定FX/Guest身份和收据保存在应用私有目录 `native/network-changes`，不含凭据。稳定身份包括FX路径/可执行哈希/进程实例、SSH目标与Guest boot，SSH重认证本身不使同目标收据失效。root每次仍验证当前连接身份。计划漂移不执行；无可信收据不猜恢复值。

部分失败尝试一次有界恢复；失败/模糊结果显示实际残留值或未知，不能显示成功。密码拒绝、无凭据、策略拒绝等不会再用同一密码重试“恢复”。手动恢复再次预览/确认，拒绝外部漂移、接口变化和不同boot/FX。恢复sysctl值不等于恢复已被关闭的连接或地址生命周期。

sudo通过已有统一生产执行器，每次独立调用使用 `sudo -k -S` 固定提示，验证与命令处于同一次SSH调用，不依赖其他会话缓存；命令stdin与密码隔离。不改sudoers/NOPASSWD/Host Key要求。1188d59的引用原则保留。诊断/网络设置/独立sudo检查不需要游戏专用CDP转发，但仍核验发布者/进程归属/端点/SSH peer/boot；游戏启动继续要求原专用后端。

Memory-Only沿用已整合SessionCredentialManager，SSH与sudo独立，切目标/身份变化/退出清除，不调用Keychain，不持久化密码，不做旧凭据迁移或删除。Security.framework的代码签名验证仍保留，不能与Keychain依赖混淆。

## 4. 只读诊断实现与实机证据

生产实现：`Core/NetworkDiagnosticsService.swift`。Native Core生成并解析协议；Guest只执行固定shell工具，不恢复Python解释器/Bridge。参数不接受任意目标或远程脚本。查询仅通过可信现有master，断连时ProxyCommand=false禁止回退认证；诊断不获取sudo。

所有探测都有整体CoreContext截止时间与取消，curl/UDP/SSH亦有单项上限。没有改IPv6、代理、DNS、防火墙、路由、Steam、游戏或EAC的分支。curl写入目标仅/dev/null；UDP文件描述符对应网络套接字，不是配置文件。

| 实机项目 | 状态 | 本轮证据/边界 |
| --- | --- | --- |
| Host只读样本 | PASS（执行） | 2026-11-04 17:04:16 +08:00，生产curl参数执行真实探测；没有任何配置修改 |
| Host Steam TLS结果 | NOT TESTED（未取得通过证据） | curl28 / TIMEOUT（3s）；不是网络不可用的结论 |
| Guest身份与VM探测 | BLOCKED | 无可验证的现有SSH master；未获取新密码/认证 |
| Guest PlayFab/UDP实测 | NOT TESTED | 因上述身份前提未执行，不伪造PASS |
| Guest只读IPv6前后比较 | NOT TESTED | 没有Guest连接，不把历史快照当本轮值 |
| Guest真实开/关/恢复 | NOT TESTED | 尚未授权，本轮没有sudo写入 |
| Native安全输入与独立SSH sudo真实验收 | NOT TESTED | 生产执行器隔离通过不代替实机密码验证 |
| 游戏真实启动、菜单、单人、EAC、多人 | NOT TESTED | 没有执行；没有从进程或TLS推断成功 |

证据：候选目录 `Test-Reports/network-live-readonly.json`。它是原始但已限字段的JSON，只包含固定目标、结果与错误码，无密码/令牌/账号/公网地址。

## 5. 自动化、安全与界面验证

| 类别 | 状态 | 结果 |
| --- | --- | --- |
| Swift Native Core | PASS（隔离） | 62检查；配置/哈希/分发 |
| Native集成 | PASS（隔离） | 22检查 |
| 网络/IPv6专项 | PASS（隔离） | 66检查：开启/关闭/混合/未知、取消、精确快照、幂等、部分失败、自动/手动恢复、恢复失败残留、无可信快照、身份变化、认证拒绝不重试、真实生产脚本在临时文件系统执行、STUN事务/长度、TLS证书失败、暂停/超时/取消和启动链 |
| SSH | PASS（隔离） | 28检查 |
| 独立sudo执行器 | PASS（隔离） | 30检查；生产执行器+合成sudo/transport，无时间戳缓存依赖 |
| 凭据管理 | PASS（隔离） | 25检查；角色复用/清空/目标切换/日志脱敏 |
| FX身份 | PASS（隔离） | 16检查 |
| 启动/GUI状态机 | PASS（隔离） | 18检查；不是实际游戏启动 |
| FX选择/性能 | PASS（隔离） | 17+15检查 |
| Swift合计 | PASS（隔离） | 299检查 |
| 检查器负向fixture | PASS（隔离） | 本地化8、截图8、历史发行10、更新资源5，共31 |
| 十语言 | PASS（静态） | 每种531/531；无缺失/重复/占位符；既有语言未删除 |
| README/CHANGELOG | PASS（静态/人工范围审阅） | 双语一致性15检查；功能/发行边界审阅 |
| 凭据API/持久化 | PASS（静态） | Memory-Only检查；没有Keychain凭据API，签名API保留 |
| 源码/候选秘密扫描 | PASS（启发式） | 暂存43文件、候选78文件；合成测试密码明确fixture前缀。扫描不是绝对无秘密证明 |
| 真实窗口截图 | PASS（限定范围） | 18张中英文实际Debug窗口，包括environment-network；检查新增面板布局、语言、未检测状态、Settings凭据区与截断；不伪造成功状态 |
| Debug构建 | PASS | 最终冻结源码xcodebuild Debug成功 |
| Release构建 | PASS | 干净提交的arm64优化Release成功 |
| 图标/资源/签名 | PASS（本地） | 原AppIcon、Assets、10lproj、launch哈希、无Python/Bridge、ad hoc codesign严格验证 |
| 候选独立启动 | PASS（Host） | LaunchServices独立路径；PID 93677；CoreGraphics真实可见窗口1180×850 |
| 真实交互/辅助功能/十语言自然度 | NOT TESTED（完整验收） | 双语截图和十语言资源校验不等于全语言人工互动验收 |

请求的50项场景分布在上述专项与原有回归内：IPv6启动解耦为生产调用链与兼容函数检查；事务失败/恢复为注入IO和真实生成脚本的隔离执行；SSH/sudo为生产执行器的模拟输运；Guest修改/真实游戏/多人一律没有升级为PASS。

## 6. 候选制品

- App：`/Volumes/Thunderbolt2TB/HD2-App-Builds/Candidates/104beaa-steamos-network-20261104/HD2FXNative.app`
- 构建提交：`104beaaf2701bedea7fb3f27707f5e853f98fcd1`，source_dirty=false。
- 版本：0.1.0，build `2026110404`，Core `1.2.0`。
- 构建时间：`2026-11-04T09:23:22+00:00`（北京时间2026-11-04 17:23:22）。
- 可执行SHA-256：`bb7babd9e8e151900eb845812995fc27bbfea766c0b04559d46fbffcdd566bc1`。
- `CANDIDATE_METADATA.json`包含完整身份；`Test-Reports/`保存分项检查、编译/构建、包检查与只读实测记录。
- 签名为本地ad hoc；没有Developer ID/公证或普通用户分发验收声明。

本轮Latest未更新。候选交付前后核验Latest可执行仍为 `50d176122baf1d7fec1c06770151c69208f708b62c0704d18120a27968012f45`，来源918db0a；未删除历史Releases、未改FX偏好、未改Guest或游戏、未合并main。

## 7. 未完成事项与下一步

1. 在候选App中由用户完成SSH安全输入/身份验证，复测VM/Steam TLS/PlayFab/UDP；本机SteamTLS超时需真实路由证据，不能自动调整代理/DNS。
2. 用户审阅精确计划并另行授权后，才真实验证IPv6开/关/恢复及独立SSH sudo。不得复用聊天密码或修改sudoers。
3. 真正游戏启动与多人验收均需另行授权。本候选不宣称全新FX即可运行HD2。
4. 其他Python遗漏按矩阵评估后另开实施范围，不顺带安装FEX/JE、改prefix、更新FX或覆盖Latest。

主参考：[网络使用说明](../STEAMOS_NETWORK_SETTINGS.md)，[功能矩阵](../PYTHON_TO_SWIFT_FEATURE_PARITY_AUDIT.md)。Linux控制项语义与STUN格式的一手依据链接位于网络说明内。
