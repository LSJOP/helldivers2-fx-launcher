# 依赖与安装边界

本清单从导出的代码读取，表示当前脚本的兼容性检查条件，不表示已经验证所有同版本组件都能运行。

## Host

- Apple Silicon Mac；其他硬件与最低 macOS 版本尚未验证。
- Python 3.9 或更新版本（当前验证解释器为系统 Python 3.9.6）；启动器仅用标准库。
- macOS 自带 SSH、zsh、网络及偏好命令；Keychain 为可选功能。
- Node.js，必须能直接使用全局 `fetch` 和 `WebSocket`；不需要 npm 包。可手动执行 `node -e "console.log(typeof fetch, typeof WebSocket)"` 检查，两项应为 `function`。这里没有核验最低 Node 版本。
- 本方案使用的本地代理端口 7890，以及从 Guest 可访问的 Host 网关 192.168.127.254；FlClash 配置、订阅、节点由使用者自己准备，不包含在仓库里。

## 缺少的运行组件

仓库内保留兼容路径，但**不包含下列二进制**：

| 组件 | 脚本预期路径／版本 |
| --- | --- |
| 专用 FX 应用 | `performance-stutter-20261027/FX HUD隔离诊断.app` |
| EIM 网络转发程序 | `goal-fx-multiplayer-20261026/gvproxy-eim`；wrapper 已包含 |
| Guest Proton-JE | `~/.local/share/Steam/compatibilitytools.d/proton-je-11.0-20261014-3` |
| Guest FEX | `~/.local/share/Steam/steamapps/common/FEX-Emu/usr/bin/FEX` |
| Wine 系统组件 | 上述 Proton 的 `files/lib/wine/`，需要匹配组件哈希 |
| Steam 与游戏 | 使用者自己安装、登录、下载；不包含 Guest 磁盘映像 |

准确的组件哈希和路径见 [机器可读清单](../runtime-requirements.json)。不要通过删除哈希检查来绕过缺失依赖。相同产品名或随意替换的新版本不能视为兼容；公开下载链接、补丁源码与可复现构建步骤仍待整理，当前源码包没有自动安装这些组件。

脚本保留 `Path.home()` 下的通用 Codex runtime Node 查找候选作为原有行为；这是动态路径模板，没有包含作者用户名，普通使用者应自行安装 Node。

## 配置与启动

首次运行通过菜单填写自己的 SSH host、端口、用户名及认证方式。默认 `127.0.0.1:2222` / `steamos` 是本地虚拟机示例，不含密码。实际首次认证仍由使用者完成。

设置写到 `~/Library/Application Support/Helldivers2FXLauncher/`。选择记住密码才写入 macOS Keychain。不要上传这个用户目录，也不要把 Steam 用户目录、FX Guest 映像、FlClash 配置或 SSH 文件加入仓库。

当前脚本固定的资源预算与网络方案应由发布维护者在更多机器验证后再泛化。本次只整理发布副本，没有替换组件、修改原始启动链或执行真实启动。
