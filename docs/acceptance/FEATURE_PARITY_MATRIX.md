# Python → Swift 功能对照

验收日期：2026-11-05（Asia/Shanghai）。源码基线 `8ba547c390d52971a7740a1970411c9e153c44b7`；验收分支 `audit/full-acceptance-20261105`。修复构建提交及 SHA-256 以候选目录的 SOURCE-COMMIT.txt / executable-sha256.txt 为准。基线 App 0.1.0 / 2026110411；修复构建 App 0.1.0 / 2026110501。未声称已发布 v1.0.0。

证据根：`native-app/evidence/`（本地忽略，交付时复制到候选 Evidence）。PASS 只适用于记录的范围；单元/隔离替身结果不代表真实 Guest 或游戏。未执行的真实项目一律 NOT TESTED，缺少前提的项目 BLOCKED。截图为真实 Debug App 窗口，非模拟 UI；抽查不代表全部交互已验收。

原项目：`/Volumes/Thunderbolt2TB/绝地潜兵脚本/HD2-StonkGuy-Fork-20261024`。本次只读比较 `goal-dxmt-20261026/start-hd2.py` 的 connect/activate_fx/wait_for_game/monitor_playfab/monitor_udp/state 及 `launcher-20261026/network_diagnostics.py`、现行 Swift Core，并参考仓库已有 FUNCTION_MIGRATION 与 PYTHON_TO_SWIFT_FEATURE_PARITY_AUDIT；未重新逐行审计所有历史诊断脚本。无证据判定原功能已失效；不声称全量 Python 完整等价。

| 功能 | 原始脚本 | Native App | 迁移结论 | 实际测试/结果 |
|---|---|---|---|---|
| FX 发现/选择 | dependency_discovery/fx_versions | FXDiscoveryService/FXSelectionManager | 部分迁移（实现已具备，真实边界未全面验证） | HOST-01/02，FIX-01/02 |
| FX 启动 | start-hd2.py activate_fx | LaunchService.startFX | 部分迁移 | 真实启动 NOT TESTED |
| 停止/重启 VM | 历史脚本/手动操作 | 安全后端禁用 | 未迁移/不可用 | 不得强杀补齐 |
| Guest SSH/身份 | guest_safety/preferences/launch_safety | SSHTransport/GuestService | 部分迁移 | 隔离通过；LIVE NOT TESTED |
| 独立 sudo | remote-admin/SSH helpers | GuestPrivilegedExecutor | 部分迁移 | 每次 stdin 认证；LIVE NOT TESTED |
| 凭据 | 历史记住凭据路径 | SessionCredentialManager | 完整迁移为内存策略（实现） | 25 隔离检查，真实重启未测 |
| IPv6 | guest_ipv6_disable/ensure_ipv4 | SteamOSNetworkService 独立控制 | 部分迁移且行为有意改变 | 不再游戏启动自动写入 |
| VM/Steam TLS/PlayFab/UDP | network_diagnostics/start-hd2 probes | NetworkDiagnosticsService | 部分迁移 | 真实 Guest 不在线；STUN不证明联机 |
| Steam 启动/游戏启动 | start-hd2.py/guest_safety | GuestScripts/LaunchService | 部分迁移 | 菜单/单人/多人未测 |
| 游戏进程监控 | wait_for_game/post-launch | GuestService/observe_launch | 部分迁移 | 进程≠主菜单 |
| 性能 CPU/RAM/Vulkan | configure/runtime args | PerformanceConfigurationService | 部分迁移 | 1.9.9 写入不支持；实际写入未测 |
| 配置备份恢复 | preferences/历史备份 | ConfigurationService/receipts | 部分迁移 | 隔离往返通过；真实 GUI 未测 |
| 日志 | network_diagnostics stores | DiagnosticsService/Store | 部分迁移 | 隔离脱敏通过；GUI 复制导出未测 |
| 多语言 | 原十语言 catalogs | Native 581 keys ×10 | 部分迁移 | 静态通过；人工自然度未测 |
| 自动更新 | update checker | Sparkle/UpdateReleaseService | 部分迁移/发布受阻 | 无生产签名包 |
| 首次环境部署 | 既有部署环境/配置脚本 | EnvironmentDeployment/adapters | 部分迁移 | 审核 FEX/Proton 制品缺失 |
| Node CDP/脚本目录 | steam-cdp.mjs/check_node.cjs | Native Core + bundled resources | 完整替换（实现） | bundle 无 Python/Node依赖 |
| Wi-Fi/代理配置 | network_profile/Steam drop-ins | 守卫配置/只读检测 | 部分迁移 | 真实写入未测；无自动修复保证 |
| EAC/多人 | 历史观测 | 仅不作成功推断 | 无法验证 | NOT TESTED |

总体 PYTHON FEATURE PARITY：PARTIAL。
