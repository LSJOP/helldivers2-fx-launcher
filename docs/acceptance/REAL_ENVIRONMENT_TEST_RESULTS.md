# 真实环境结果

验收日期：2026-11-05（Asia/Shanghai）。源码基线 `8ba547c390d52971a7740a1970411c9e153c44b7`；验收分支 `audit/full-acceptance-20261105`。修复构建提交及 SHA-256 以候选目录的 SOURCE-COMMIT.txt / executable-sha256.txt 为准。基线 App 0.1.0 / 2026110411；修复构建 App 0.1.0 / 2026110501。未声称已发布 v1.0.0。

证据根：`native-app/evidence/`（本地忽略，交付时复制到候选 Evidence）。PASS 只适用于记录的范围；单元/隔离替身结果不代表真实 Guest 或游戏。未执行的真实项目一律 NOT TESTED，缺少前提的项目 BLOCKED。截图为真实 Debug App 窗口，非模拟 UI；抽查不代表全部交互已验收。

## 已执行

- 实际读取并严格签名校验 FX 1.9.4、1.9.8、1.9.9；摘要在 host-readonly.json。
- 生产 Swift NativeCoreService 对实际 1.9.8/1.9.9 调用发现、资源检查、运行状态；FX 均未运行。实际发现缺陷及修复复测分别在 host-native-results.jsonl / host-native-retest.jsonl。
- 独立 Debug capture bundle ID，zh-CN/en 各七页面+三个详情区域，20 张真实窗口截图。仅进程偏好隔离；底层配置只读读取现有 App Support，因此不是完整干净用户首次安装验收。
- 独立 Release 副本 8 秒存活、仅终止本次创建进程，不等于 Release GUI 验收。

## 待用户授权的操作

1. 明确指定 FX 1.9.8 或 1.9.9 路径，授权启动 FX/Guest，以进行真实身份绑定、SSH 和独立只读 sudo 检查；密码仅在 App 安全输入框输入，不在聊天提供。
2. 授权 Steam/游戏启动后验证主菜单；单人任务及多人任务分别确认实际结果。
3. IPv6、FX 性能参数、首次部署写入仍需逐项精确目标/原值/新值/备份/恢复预览后授权；本报告不是批量修改申请。
4. 更新安装限隔离副本，但需先有可信签名包；缺少包不能靠授权绕过。

上述尚未授权/执行，均 NOT TESTED 或 BLOCKED。没有关闭/绕过反作弊，没有更改 sudoers/NOPASSWD，没有删除/替换虚拟磁盘或升级运行组件。

修复版 Release：3次有界启动/窗口检测/退出，实际 on-screen window 均为1。仅4秒/轮、单台系统、隔离 bundle ID，无 Guest；完整稳定性仍 NOT TESTED。证据位于候选 release-gui-results.json/release-window.png。

## 收尾状态变化

收尾进程检查发现 `/Applications/FX 绝地潜兵2（脚本专用）.app` 的 FX 1.9.4 进程7797/7801及gvproxy正在运行，进程开始时间2026-11-05 02:29:47（本地）。早先 HOST-02 的未运行结果只对应当时快照。启动来源未经确认，本任务未主动发出 FX 启动操作，不把外部状态变化计为启动 PASS；未连接 Guest、未终止这些进程。真实 SSH/Guest/游戏验收仍需用户授权。

## 用户授权后的真实只读验收 · 2026-11-05

用户明确授权启动现有 FX 1.9.8，检测身份、SSH、独立只读 sudo 与网络；不包含配置修改/Steam或游戏启动。最初检测到另一份测试用 FX 1.9.9，未终止它；随后复查已退出，才继续1.9.8。

| 编号 | 目标 | 操作/预期 | 实际结果 | 状态 | 证据 |
|---|---|---|---|---|---|
| LIVE-FX-01 | 指定 FX 1.9.8 启动及宿主身份 | 生产 NativeCoreService preflight_launch → start_fx；只允许已授权指定路径 | 资源与发布者校验通过；启动完成，supervisor+VM子进程2个，实际gvproxy监听127.0.0.1:2222，transport_verified=true | PASS（宿主范围） | Evidence/live-readonly-20261105/authorized-fx-start.jsonl |
| LIVE-AUTH-01 | Guest 身份及 SSH 密码 | 已打开正式候选并进程参数指定1.9.8；密码仅App安全输入框 | 等待用户在App输入并运行认证；端口开放不代表认证成功 | NOT TESTED / 等待输入 | 无认证结果 |
| LIVE-SUDO-01 | 独立只读 sudo | 当前会话独立sudo密码，生产逐次执行器 | 等待用户App输入；未使用聊天/argv/env接收秘密 | NOT TESTED / 等待输入 | 无认证结果 |
| LIVE-NET-01 | VM/Steam TLS/PlayFab/UDP | App运行环境页显式启动真实只读探测 | 等待上述认证及用户执行；未修改IPv6/代理/Guest配置 | NOT TESTED | 无真实探测结果 |

FX启动由本次生产源码CLI验收驱动调用同一Native Core完成，构建来源6dd08fb（Core与候选构建提交3967534相同；中间仅文档提交）；不能声称GUI启动按钮已完整通过。第一次宿主CLI在错误工作目录执行导致测试资源根缺失，已保存initial-wrong-resource-root.jsonl并在正确native-app目录复查；该工具调用错误不是App资源缺失。

候选App已打开用于输入凭据；本次没有启动Steam或游戏命令，不推断Guest自身启动服务的状态。原有最终摘要中的真实认证/游戏NOT TESTED状态仍有效；FX管理只有启动/宿主身份新增PASS，其他管理动作仍未测。

## 用户 SSH 报错定位 · 2026-11-05 02:50 后

截图显示CheckingFXEntry阶段FX_INSTANCE_MISMATCH。实际复核：界面选定自定义路径FX 1.9.8/SSH2222；运行中为`/Applications/FX Steam Launcher测试用.app` FX1.9.9（supervisor9382/子进程9389，02:46:04启动），对应gvproxy9387监听SSH2223。原1.9.8进程已不在当前快照。属于真实不同副本/端口，当前证据不支持判定为实例识别误报；未传送密码、未进行sudo、不自动切换目标或停止现有VM。身份守卫拒绝PASS；SSH认证仍NOT TESTED，不记为密码失败。证据：Evidence/live-readonly-20261105/ssh-entry-error-0250.json。

## 改测 FX 1.9.9 · 用户明确授权

再次检查时“测试用”副本已退出，Bundle ID变为es.fxgam.steamtc，发布者要求不通过。标准`/Applications/FX Steam Launcher.app`为1.9.9、es.fxgam.steamac，发布者要求通过；改用这份标准副本执行同一生产Native Core的preflight/start_fx，不放宽身份验证。启动参数来自现有配置（SSH2222、CPU8、内存8192、kosmickrisp），未持久修改FX或Guest配置，未发出Steam/游戏启动命令。实际监听127.0.0.1:2222。

App现有窗口仍需在FX管理切换到标准副本；用户须重新输入内存凭据并运行SSH/sudo/网络。未接收密码，未把启动/端口监听等同于Guest认证成功。证据：Evidence/live-fx199-20261105/。

### 测试驱动资源路径修正（未冒充App缺陷）

发现首次1.9.9启动的CLI驱动将HD2FX_LAUNCH_RESOURCES指向源码Resources/launch，而候选App生产实例使用App bundle的launch资源路径。虽然字节/摘要一致，App精确进程路径绑定仍可能拒绝此实例；这属于验收驱动错误，不能判为SSH认证失败或绕过安全检查。已修正驱动指向候选App资源并编译，尚未重新执行启动。正常退出本次测试FX的AppleEvent返回-128“用户已取消”，未使用kill/强杀。已请用户正常退出后直接通过App选择标准1.9.9并启动，使实际GUI路径和后端资源一致。真实SSH/sudo/网络仍NOT TESTED；1.9.9实际宿主启动PASS范围保留。

## 用户确认：Native App 启动进入主菜单/舰桥 · 2026-11-05

用户先反馈“成功进入游戏”，随后明确确认：“从 Native App 启动，已到主菜单或舰桥”。本次在已授权改测FX1.9.9的上下文中记录。

| 编号 | 目标/环境 | 执行步骤与预期 | 实际结果与证据 | 状态 | 构建来源 |
|---|---|---|---|---|---|
| LIVE-GAME-USER-01 | Native启动到游戏/当前1.9.9验收会话 | 用户通过Native App启动，实际到达菜单/舰桥 | 用户明确确认，user-confirmed-main-menu.json；不凭进程数量推断 | PASS（用户确认） | 候选0.1.0/2026110501，3967534413ed8cde9ac8c0d8f5f4c4b5f4e5ae17；未重新从GUI读取运行构建元数据 |
| LIVE-MENU-USER-01 | 主菜单或舰桥 | 用户实际看到主菜单/舰桥 | 用户明确确认该阶段；非本工具截图独立确认 | PASS（用户确认） | 同上 |
| LIVE-MISSION-USER-01 | 单人任务 | 实际进入单人任务 | 尚无确认 | NOT TESTED | 同上 |
| LIVE-MULTIPLAYER-USER-01 | 多人任务/EAC | 加入并完成多人任务/观察EAC | 尚无实测结果；菜单成功不证明多人或独立EAC验收 | NOT TESTED | 同上 |

该证据覆盖先前摘要中“HELLDIVERS 2 LAUNCH”和“GAME MAIN MENU”的NOT TESTED为PASS（用户确认）。不自动将独立sudo、SSH异常矩阵、VM/TLS/PlayFab/UDP诊断、CPU/RAM/Vulkan写入、新VM首次部署或多人改为PASS。真实游戏成功范围为这一次会话，不是全版本兼容/全部故障分支通过。未再次启动或发送Guest命令，不干扰用户游戏。
