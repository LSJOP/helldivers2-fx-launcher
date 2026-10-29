# 启动配置安全 / Launch configuration safety

[README](../README.md) · [架构 / Architecture](ARCHITECTURE.md) · [依赖 / Dependencies](DEPENDENCIES.md) · [更新日志 / Changelog](../CHANGELOG.md)

## 简体中文

本地安全修复保留原有 FX → SSH → Steam → FEX/Proton → 游戏链路与核心参数。版本仍由 [VERSION](../VERSION) 提供。以下描述代码行为，不代表已经完成实机启动验收。

### 启动前与确认

UI、`menu.py --launch`、兼容入口和直接运行后端脚本使用统一启动检查。后端也重新检查基础文件及本地游戏依赖，并取得当前 macOS 用户共享的 FX 启动互斥锁，覆盖不同端口、设置文件和项目副本，避免端口别名指向同一 Guest 时并发写入。锁不会终止其他进程；启动期间更改 SSH 设置会取消操作。

启动准备先显示待检查项目，随后根据真实读数更新。Guest 写入前必须关联以下证据：

- 唯一的指定 FX 可执行进程及其启动时间、gvproxy 子进程关系与已知二进制哈希。
- SSH listener 属于该 FX 进程树；实际 SSH master 的 TCP peer 对应此端口。
- 本地 CDP listener 由同一 SSH master 持有，master 参数包含指向该 Guest `127.0.0.1:8080` 的预期转发。
- Guest boot ID 与预期图形标记；原有兼容组件校验继续保留。

证据缺失、进程关系不符、master 转发无法识别或环境变化时，标记未验证并阻止写入。**不提供强制跳过。此关联方案仅通过 Mock 测试，尚未证明适用于真实 FX 的所有进程拓扑**；不兼容的拓扑需要先读取证据再适配。

以下实际配置变更需要用户查看完整前后值，并输入 `APPLY`：

| 项目 | 行为 |
| --- | --- |
| Guest IPv6 | 读取全部接口原开关，只写需要改变的目标。`all` 可能联动其他接口和 `default`，预览包含该影响。使用的是 **Guest sudo，不是 macOS sudo**。 |
| Steam 代理 | 仅管理 `90-hd2-proxy.conf` 中本程序已知内容；未知内容／符号链接不覆盖。运行中的 Steam 需要一次受控停止／恢复时会明确展示。 |
| 游戏启动项 | 从 Steam API 读取完整字符串；不猜测合并自定义参数。选择保留并取消，或确认替换为已有完整配置。写入前再次比较当前 API 值。 |

无需变更时不要求对应配置确认。Steam 服务已停止且没有活跃游戏时最多执行一次正常启动；Steam 已运行时不重复启动。服务状态未知、过渡中或发现独立 Steam 实例时停止操作，不使用全局 killall／pkill。

### 备份、失败与恢复

备份保存在本地 `launcher-20261026/backups/`，单个文件权限 `0600`，Git 忽略该目录。**备份可能包含个人启动参数，不能上传或分享。**

单个 Guest 事务失败会尝试恢复本次改变的开关／本程序的代理文件与原有 Steam 运行状态。后续启动步骤失败时，按逆序尝试恢复已记录的配置变更。原来停止的 Steam 不会因为回滚被强行启动；由正常启动步骤启动的服务不承诺回到停止状态，恢复摘要会保留此边界。

恢复前重新验证身份、游戏空闲状态和当前配置。配置被外部修改、游戏已启动、接口集合变化、SSH 中断或远端操作结果不明时，不强行恢复。远端结果未知时暂停后续写入，避免与仍在运行的事务竞争。摘要列出需要手动检查的备份路径；不会自动重跑整个启动过程。

手动处理时先确认目标 FX 与当前 Guest，再查看备份和现值：启动项可在 Steam 游戏属性中恢复备份的 `launch`；IPv6 备份中的 `plan.ipv6` 为原开关；代理备份记录原内容及原服务状态。**不要将另一台 Guest 的备份直接套用到当前环境。** 无法核实身份时保持只读。

IPv6 恢复只验证 sysctl 开关，不能保证先前动态 IPv6 地址／路由立即重建。SSH 丢失、systemd 失败和并发的外部写入均无法保证自动恢复。没有修改 macOS IPv6、Wi-Fi、DNS 或默认路由。

### 成功证据与限制

- 游戏进程出现，仅表示进程检测通过。
- EAC 只解释本次游戏请求之前记录游标之后新增的日志。游标包含文件身份、大小、偏移及内容校验点；旧成功记录不能补齐本次结果。
- 截断／轮转／新路径先建立新游标，等待后续内容；可能保守地漏掉新文件首次写入的成功记录，此时显示未验证。
- 日志缺失或读取失败显示未验证；进程、EAC 日志与真实联机成功互不替代。
- 八阶段保留实际状态与耗时；没有完成百分比或剩余时间估算。TLS／STUN 结果仍不证明 NAT、P2P 或匹配成功。
- 原有启动后 TLS／STUN 探测行为未调整；本次测试全部隔离，没有执行探测。

Linux `all/disable_ipv6` 的联动语义参见 [Linux 内核文档](https://docs.kernel.org/networking/ip-sysctl.html#ipv6-variables)。预览版仍依赖指定组件、固定代理假设和 Guest 布局；这不是完整运行环境安装器。

## English

This local safety update retains the FX → SSH → Steam → FEX/Proton launch chain and its existing core parameters. It does not establish a successful real-device launch.

The maintained UI, CLI, compatibility entry and backend executable share launch checks. The backend rechecks local requirements and serializes FX launches for the current macOS user across ports, settings files and checkout copies; different port aliases can reach the same Guest. Changing SSH settings during launch cancels the operation.

Guest writes require cross-checking the exact FX process, its gvproxy descendants, the SSH listener, the actual SSH master's peer, ownership and destination of its CDP forwarding, and the Guest boot identity. Missing or inconsistent evidence blocks writes. **This association has only been simulated; real FX process topologies remain unverified. There is no force override.**

Actual Guest IPv6, managed Steam proxy and LaunchOptions changes display complete before/after values and require typing `APPLY`. Unchanged settings need no corresponding configuration confirmation. IPv6 uses Guest sudo, never macOS sudo. The `all` switch can affect every interface and the default value. Custom Steam arguments are never guessed or merged; users can preserve them and cancel, or approve the existing full configuration. The complete live API value is backed up and compared again before writing.

Only recognized launcher proxy content is managed. Unknown content and symlinks are refused. A stopped, idle Steam service receives at most one controlled start. An already running service is not started again; unknown/transitional states and independent Steam processes block service changes. No global process-kill commands are used.

Private backups stay in `launcher-20261026/backups/` with mode `0600` and are ignored by Git. Do not upload them: LaunchOptions may contain personal data. Failed transactions attempt narrowly scoped recovery; later launch failures attempt recorded changes in reverse order. Recovery never starts Steam merely because it was originally stopped. A service started by the normal launch step is not guaranteed to be stopped again during recovery.

Identity changes, active games, changed interface inventories, external edits, SSH loss or an unknown remote outcome can require manual recovery. Unknown in-flight outcomes stop further writes. Inspect the listed private backup only after identifying the correct Guest. Steam properties can restore the saved `launch`; IPv6 snapshots are under `plan.ipv6`; proxy backups include original content and service state. Do not blindly apply another Guest's backup. Restoring IPv6 switches does not guarantee immediate restoration of dynamic addresses/routes. Host IPv6, Wi-Fi, DNS and routes are untouched.

EAC uses a pre-request file identity/offset/checkpoint baseline and only new log bytes. Rotation, truncation and newly discovered paths establish a fresh cursor conservatively; missing or ambiguous evidence remains unverified. Process detection, EAC log evidence and multiplayer success remain separate. The eight phases retain status and elapsed time without estimated completion percentages. Existing post-launch TLS/STUN probes remain; no live probes or game launches were performed in safety tests.
