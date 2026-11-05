# HELLDIVERS 2 成功环境基准

状态：**LOCKED FROM EVIDENCE**，不是针对新版 FX 或 SteamOS 的通用兼容性声明。应用可以检测任意新版本，但只能在与本基准匹配时自动修改环境。

| 项目 | 已验证值 | 证据等级 |
|---|---|---|
| FX | 1.9.4 | 冷启动复现 |
| Guest | SteamOS 0.4.5, aarch64 | 快照观测 + 复现 |
| FEX | StonkGuy eac-main-20261022 + PR6 + PR7 + local PR20 RF candidate | 复现；可执行文件 SHA-256 `ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf` |
| Proton | `proton-je-11.0-20261014-3` | 复现 + 上游发布资产 |
| Proton 归档 | 348,245,820 bytes | SHA-256 `aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485` |
| Proton ntdll | `files/lib/wine/x86_64-windows/ntdll.dll` | SHA-256 `a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe` |
| 图形 | Vulkan + KosmicKrisp | 设置快照 + 成功会话 |
| 受管启动参数 | `FEX_NEEDSSECCOMP=1`, `FEX_DISKCACHE=0` | 成功运行环境记录 |

其他已观测参数包括 `WINEDEBUG=-all`、`PROTON_USE_XALIA=0`、`PROTON_LOG=1`、`PROTON_LOG_DIR=/tmp`，但尚未证明它们都是必要条件，因此不强制覆盖用户值。代理地址属于会话特定值，不得写入通用基准。

验收证据：冷启动复现、单人落地与移动、四人任务及结算均有历史记录。这不代表所有主机、网络或未来版本均保证成功。

IPv6 政策：只诊断、可显示橙色提示，不自动修改，不阻塞部署，不是成功基准的必要条件。

机器可读版位于 `native-app/Resources/successful-environment-baseline-v1.json`。
