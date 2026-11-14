# FX SteamOS 新镜像基线 · 2026-11-15（Asia/Shanghai）

## 环境概览

检查通过本机测试 FX 的回环 SSH 端口 2223 完成。监听进程为测试 App 内的 gvproxy，VM 进程实际打开新镜像。新镜像的 SSH 主机密钥与原镜像不同，本次使用独立临时主机密钥文件，保留现有 SSH 配置。检查只读取配置、清单、文件和进程状态。镜像处于运行状态，记录是观测基线，不能作为离线备份。

| 项目 | 实测 |
|---|---|
| FX | 1.9.9，测试 App /Applications/FX Steam Launcher测试用.app |
| 镜像 | /Volumes/Thunderbolt2TB/steamos-1.img，144286154752 字节 |
| SteamOS | 0.4.5，BUILD_ID 20261022.6150929 |
| 内核、架构 | Linux 7.2.9-steamac，aarch64 |
| VM CPU、内存 | 8 个逻辑 CPU，Guest 可见内存约 11 GiB，交换空间约 5.8 GiB。CPU 型号未报告 |
| 图形 | 系统存在 freedreno 和 virtio 的 aarch64 Vulkan ICD，/usr/share/guestos/fex-mesa 下另有 x86 和 x86_64 ICD。DRM 路径观察到 virtio-mmio，lspci 无可用访问方式。实际 Vulkan 设备、驱动版本、FX 渲染后端未确认 |

## FEX、RootFS 和兼容工具

Steam 默认库不存在 steamapps/common/FEX-Emu。PATH 中未找到 FEX 或 FEXInterpreter，系统存在 /usr/bin/FEXBash，Proton 自带 libwow64fex 和 libarm64ecfex。未确认这些组件的 FEX 源码版本、补丁状态或哈希。缺少独立 FEX-Emu 目录不能据此判定系统完全没有 FEX。该目录的 emulator.json、ConfigTemplate.json 和 VERSIONS.txt 均无法读取。实际 RootFS 路径、注册信息和生效的 FEX 环境变量未确认。

已发现 Steam 默认库中的 Proton 11.0 (ARM64)，version 文件为 `1791559733 proton-11.0-2e-arm64`。SteamLinuxRuntime_4-arm64 的 depot 为 `4.0.20261021.265997`，pressure-vessel 为 `0.20261007.0`。默认 Steam 路径下没有 compatibilitytools.d，未观察到 Proton-JE 目录。游戏实际选择的工具、启动参数及其他库中的自定义工具未确认。

## 关键文件与 SHA-256

Guest Steam 路径以前缀 /home/steamos/.local/share/Steam 为基准。

| 路径 | SHA-256 |
|---|---|
| /Applications/FX Steam Launcher测试用.app/Contents/MacOS/steamac-vm | be281f1d430d24b5147229f032fe44f9d3b25171ab7f2a560e792bfc9962cb99 |
| steamapps/common/Proton 11.0 (ARM64)/proton | a4f94c208355639c87877ba63e8faf1f26d8c0731db04f722dee66cdfcfbf478 |
| steamapps/common/Helldivers 2/bin/helldivers2.exe | b434f6f326b7759978265f5863ef72e3c5edd4aa5315cc1ef4b640d204eae0bb |

## 安装与后续对比

Steam App ID 553850 清单存在，installdir 为 Helldivers 2，StateFlags 为 1026，buildid 为 0。游戏 EXE 存在，大小为 28743256 字节。清单状态无法证明 Steam 已完成安装或验证 depot 完整性。检查时没有发现 helldivers2.exe 进程。Guest 未发现 ~/.local/share/HD2FXLauncher，宿主 App 的首次配置状态未确认。

此镜像已经表现出与历史 RF 加 Proton-JE 环境不同的目录和工具链。后续对比应复用上述镜像路径、系统构建号、Proton 与 Runtime 版本、Steam 清单字段及 EXE 哈希。实际启动、窗口、EAC 和联机未测试。
