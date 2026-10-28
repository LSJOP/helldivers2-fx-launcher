# HELLDIVERS 2 · FX 启动助手（源码分享包）

**最终发布目标：使用者安装指定版本的 FX 后，运行脚本准备兼容组件并启动游戏；网络使用自己的连接，不要求复刻作者的代理、节点、TUN 或有线方案。当前副本尚未完成这项通用化。** 具体阻碍和验收标准见 [通用发布审计与方案](docs/PORTABLE_RELEASE_PLAN.md)。

供已有兼容 FX 环境的 Apple Silicon Mac 用户研究、复现与测试。**本仓库不含完整运行环境，下载源码后不能直接保证启动游戏。** 当前公开副本尚未在其他 Mac 或干净环境验证。

## 包含什么

- 终端启动器、原有后端、SSH / 可选 Keychain 支持。
- 十种语言、终端图案、网络诊断和性能配置代码。
- 离线回归测试、合成测试夹具、依赖清单和本地发布扫描工具。

不包含游戏文件、Steam 账号、登录数据、密码、SSH 密钥、代理订阅、个人节点、真实运行日志、备份、网络快照、FX 应用或兼容层二进制。

## 开始前

1. 阅读 [依赖与安装边界](docs/DEPENDENCIES.md)。目前还缺少能公开复现的完整组件下载／构建流程，因此此版本是源码分享包。
2. 在终端进入本仓库，运行 `/usr/bin/python3 tools/check_dependencies.py`。它只检查本地文件和工具，不连接 SSH、不启动应用、不访问网络；缺失运行组件时以状态码 2 退出。
3. 仅在已自行准备兼容环境后，才双击 `启动绝地潜兵2.command`；首次配置填写自己的 SSH 信息。玩家自行通过 Steam 获取游戏。
4. 菜单 8 管理 SSH 设置；默认不保存密码，只有主动选择时才使用 macOS Keychain。

Python 启动器仅使用标准库；Steam 控制桥还需要提供全局 `fetch` 和 `WebSocket` 的 Node.js。系统 Python 不可用时需先安装 Python 并相应调整 `.command` 入口。不要假定所有 macOS 都预装可用的 Python。

## 操作影响

正常启动／环境配置会连接本地 FX 的 SSH，可能启动 FX / FlClash、设置 Guest IPv4、重启 Guest Steam、写入 Steam 游戏启动项和启动游戏。菜单 2 会写入 FX 的 CPU、内存及显示偏好；网络菜单内应用单有线方案可关闭 Wi-Fi。运行这些动作前请先阅读界面说明并确认适合自己的机器。

菜单 3 / 4 是运行环境检查／报告，但可能建立 SSH 认证。网络探测会访问配置的公开服务；HTTPS / STUN 成功不等于游戏 UDP、NAT、匹配或 EAC 成功。缺少证据时应以 `unknown` / `unverified` 为准。

当前脚本继承专用代理和性能假设：Host 网关 `192.168.127.254:7890`、本机代理端口 `7890`、8 CPU、8 GiB Guest 内存、6 GiB 显存预算。这些是兼容方案参数，不是所有 Mac 的推荐值。没有自动验证其适用于其他硬件／网络。

## 开发验证

```sh
/usr/bin/python3 tools/scan_release.py
/usr/bin/python3 tools/run_offline_tests.py
```

离线测试的结果见 [验证记录](docs/VALIDATION.md)。测试使用临时用户目录和进程内模拟，不能代替真实安装、游戏启动、EAC 或联机验证。

## 隐私与发布

详见 [脱敏报告](docs/SANITIZATION.md)。运行后产生的日志、备份和个人设置不要添加到 Git；`.gitignore` 已排除常见路径，但不能替代复查。

本仓库发布的是经过脱敏的实验性源码快照，尚未实现通用安装流程。第三方来源与许可边界见 [第三方说明](THIRD_PARTY_NOTICES.md)。此副本尚未指定项目源码的开源许可证；不要将其描述为已完成开源授权。

## English

Source-sharing snapshot of an experimental terminal launcher for an existing FX / Steam environment on Apple Silicon Macs. Runtime binaries and all personal data are excluded. This is not a complete installer; fresh-machine compatibility and multiplayer operation are unverified. Read `docs/DEPENDENCIES.md` before use. Launch and setup actions can modify local FX preferences, guest networking and Steam settings. Every player supplies their own account and game installation.
