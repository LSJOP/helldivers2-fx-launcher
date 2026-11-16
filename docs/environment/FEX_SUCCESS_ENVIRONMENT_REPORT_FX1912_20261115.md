# FX SteamOS 历史成功环境检查 · FX 1.9.12

文件名按任务约定保留 `20261115`；实际检查跨 **2026-11-15 至 2026-11-16 00:40（Asia/Shanghai）**。参照 [FX 1.9.9 未配置环境报告](FEX_BASELINE_REPORT_20261115.md)，保留环境概览、FEX/RootFS/兼容工具、文件哈希及安装/历史证据结构，并展开持久化检查。配套：[逐项对比与自动部署建议](FEX_ENVIRONMENT_COMPARISON_FX199_VS_FX1912.md)。

**结论：已定位持久保存在原镜像 `/home` 分区的 RF FEX、Proton-JE、Runtime 4、Steam 工具映射和启动参数；历史启动日志明确使用该路径链。不能据此声称已找出最小必要组件，也未重新验证游戏。正式盘中的 `container_environment.FEX_ROOTFS` 是空字符串，游戏配置中的 RootFS 是 `/usr/share/guestos/fex-mesa/`；本次没有发现正式盘将该参数持久写成 `/` 的直接证据。**

证据等级：**在盘实测**为本次读取文件/哈希；**宿主日志**为已有启动记录；**历史运行**为 Steam 启动记录或 FX 统计；**用户确认**为多次重启仍正常运行的说明；**SSH 实测**为用户重开 SSH 后的现场只读采样；**静态机制**为脚本内容所表达的行为；**未确认**为缺少当前进程/容器实测。等级不互相替代。

## 1. 环境概览与保护边界

### 身份与检查方式

- 2026-11-15 初查：`/Applications/FX Steam Launcher.app` 的 bundle ID 为 `es.fxgam.steamac`，版本/构建均为 `1.9.12`；宿主父进程 PID 15613、VM PID 15617，`lsof` 明确显示 VM 打开 `/Volumes/Thunderbolt2TB/steamos.img`。日志构建标识为 `1.9.12+7d9b6681c9`。E1。
- 对照实例是 `/Applications/FX Steam Launcher测试用.app`、`es.fxgam.steamtc`、1.9.9、VM PID 11593，实际打开 `steamos-1.img`，由测试 gvproxy 提供端口 2223。所有现有 SSH ControlMaster 均指向 2223，**没有把这些连接用于正式盘检查**。
- 首轮离线检查时，正式实例的偏好为 `sshEnabled=false`，启动命令 `steamac.ssh=0`，gvproxy `-ssh-port -1`；控制台记录 sshd units runtime-masked。没有尝试密码认证、开启 SSH、绕过 SSH 开关或启动其他 Guest 服务；用户提供的密码未写入文件或命令。
- 用户随后重新打开正式实例 SSH；11-16 00:33 后宿主进程与打开文件绑定同一 App、原 `steamos.img` 和端口 2222。采用已有 host key 严格校验，通过 SSH 标准输入运行只读 Python 采集，不上传脚本、安装软件或启动游戏；采集前后核对同一 Guest/boot 身份。SSH 登录及系统正常活动可能产生记账或日志写入，故不声称镜像字节完全不变。E9–E12。
- 首轮使用本机**已存在**的 `/tmp/hd2-offline-venv/bin/python -B` 与 `dissect.extfs`，以 Python `open(image, 'rb')` 解析 GPT 和 ext4 inode。首轮没有安装软件、挂载镜像、回放 journal、fsck、修改组件或运行 Guest 程序。
- 首次读取时原 VM 已在运行。继续检查时正式 VM 已退出，`lsof steamos.img` 不再出现 VM；本任务没有发出停止或启动命令。00:18 在无 VM 打开该盘的状态重新读取，所采组件/配置文件 SHA-256 与首次读取一致。原镜像 inode `1734248`、大小 `453523800064` 字节；最后一次读取前后 `mtime_ns=1794759188134160317` 一致。这里只证明本次句柄只读和重复读取一致，**没有生成完整镜像校验或可恢复备份**。E2/E3。
- 活跃 VM 自身曾写盘；不能声称整个检查期间镜像完全没有任何变化。未冻结文件系统或作冷启动实验。图像、登录状态、密码、令牌、账号 ID、机器身份及完整 VDF 不入报告/Git。

### FX 与 SteamOS 字段

| 项目 | FX 1.9.12 检查结果 | 证据与限制 |
| --- | --- | --- |
| FX App | `/Applications/FX Steam Launcher.app`，1.9.12，`es.fxgam.steamac` | Info.plist、宿主日志 E1 |
| 原镜像 | `/Volumes/Thunderbolt2TB/steamos.img`，453,523,800,064 字节 | VM 打开文件 + GPT/stat；不是测试盘 |
| SteamOS | 0.4.5；BUILD_ID `20261022.6150929` | 本次启动日志选中 `rootfs-B`，`/dev/vda5` |
| 内核 | Linux `7.2.9-steamac`，构建时间 Tue Oct 6 18:59:28 UTC 2026 | Guest `uname` 与 App Image 静态记录一致；E9 |
| CPU 架构 | Guest `aarch64`；FEX ELF e_machine=183 | SSH 实测和 ELF 静态记录；E9 |
| Guest CPU 数量 | 8 个在线 CPU，编号 0–7 | Guest 在线 CPU 和宿主分配均为 8；E9 |
| Guest 内存 | Guest MemTotal 12,216,624 KiB，采样时 MemAvailable 10,670,432 KiB | VM 分配 12,288 MiB；瞬时可用量会变化，E9 |
| Swap | `/dev/zram0` 6,108,156 KiB，采样使用 0 KiB | `/proc/swaps`、`/proc/meminfo`；E9 |
| 图形 | 启动记录 `Venus → KosmicKrisp`、`steamac.gfx=vulkan` | 宿主日志与 1.9.12 历史会话一致 |
| GPU | 宿主 Apple M4 Pro、16 GPU cores；FX 启动日志 Venus → KosmicKrisp；Guest 现有日志报告 Venus 设备 `0x106b:0x0064` | Steam 进程映射 virtio Vulkan 驱动；不是游戏进程加载证据；E9–E11 |
| Vulkan ICD | 原生 aarch64 freedreno、virtio；fex-mesa 中 x86 和 x86_64 的 freedreno、virtio | 共 6 个 ICD JSON；当前 Steam 映射 `/usr/lib/libvulkan_virtio.so`，游戏实际 ICD 未采样；E9 |
| 图形实现文件 | `Contents/Frameworks/libvulkan_kosmickrisp.dylib` | 本次 SHA-256 见第 5 节；没有加载映射实测 |

## 2. FEX、RootFS 和兼容工具

以下路径缩写仅为表格可读性，均有明确绝对前缀：

- `S = /home/steamos/.local/share/Steam`
- `F = S/steamapps/common/FEX-Emu`
- `STAGE = /home/steamos/hd2-goal-rf-20261026/stage`
- `JE = S/compatibilitytools.d/proton-je-11.0-20261014-3`
- `R4 = S/steamapps/common/SteamLinuxRuntime_4`

### 2.1 已安装 FEX 与历史 RF 文件

主程序是 `F/usr/bin/FEX`，4,597,568 字节，SHA-256 `ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf`。本次读取 ELF GNU build-id 为 `bb40813f814d70221557560c847dc90ef956010a`，二进制包含 `eac-main-20261022`。未执行 `--version`，版本字符串不是当前执行证明。E2/E4。

`F/usr/bin/FEXBash` 是 659,144 字节 ARM64 ELF，GNU build-id `60f5895a7648b51d401d0e4dad326255ad1300b7`，与 1.9.9 报告中的 `/usr/bin/FEXBash` 631 字节脚本是不同路径/角色。正式 Guest `/usr/bin/FEXBash` 同为 631 字节脚本，SHA-256 `8a907f46e455bf26d6bf2f2c09cf28e4aed6e2105a74c870a3d61c49b554e2d1`，与 1.9.9 基线相同；脚本转入 Steam 库的 FEX 和 Runtime，不能单独视为已部署 RF。E9。

安装目录 `F/usr/bin` 未见独立文件 `FEXInterpreter`，注册入口为 `./usr/bin/FEX`。保留源码中有 `Source/Tools/FEXInterpreter/`；源码目录名不等于另有一套已加载解释器。现场 PATH 及显式检查的 `/usr/bin`、`/usr/local/bin` 未找到 `FEXInterpreter` 或 FEX 主程序；这不等于穷尽全系统所有目录。E9。

RF 历史组共十文件，实测如下。**正式安装目录有九个与 stage 相同；不可写成“十个均已安装”。** E2/E4。

| 相对 FEX-Emu 路径 | 安装文件字节数 | SHA-256（stage；安装存在时已逐一比较） | 结果 |
| --- | --- | --- | --- |
| `usr/bin/FEX` | 4597568 | `ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf` | 安装文件与 stage 相同 |
| `usr/bin/FEXBash` | 659144 | `ec3e084e8ace83eee1de61d052b5d6b61f19d4ca6ca8d17180aeb39ccf512ddd` | 安装文件与 stage 相同 |
| `usr/bin/FEXGetConfig` | 396632 | `7da0614a4c1c16ac4cf92e7eae5b4bc0255722cf3675e7b30f7a5a6c06e21cde` | 安装文件与 stage 相同 |
| `usr/bin/FEXOfflineCompiler` | 4268920 | `7c7aa677f33cbc8ac5d7cff7ef693fabd6d74d162809120eb51124a281f5c03e` | 安装文件与 stage 相同 |
| `usr/bin/FEXpidof` | 265464 | `907b6801d8cbb2844b66ad8cb199cff933aa7e9b63f596ebd924179bbde9ef56` | 安装文件与 stage 相同 |
| `usr/bin/FEXServer` | 462712 | `f32cf426de3d1126bc89bdbf59bd244f9a371fe967b5c2e76437c496eea98236` | 安装文件与 stage 相同 |
| `usr/bin/FEXServerManager` | 1039792 | `02ff8a14554a8ffc91ec4c71bb2fa470c965b6f38bb5316c44e9296a3bfa4898` | 安装文件与 stage 相同 |
| `FEXCompatTool` | 1035920 | `85a86207a34c9ae286435ba7ea19aa004ef50220ddc043eeb6bc8963ce516b67` | 安装文件与 stage 相同 |
| `ConfigTemplate.json` | 324 | `e458d3fe3d0e259de3465f621b6742df16e6f0858aa8484a39fd5e47366aeb1d` | 安装文件与 stage 相同 |
| `VERSIONS.txt` | 缺失 | `e4d61eba61576bfd8ea8dae3cde90dd079b9bf000cf6352b2ff52dfbdd781fea` | **安装目录缺失；此哈希只属于 stage** |


`STAGE/VERSIONS.txt` 内容：

```text
FEX describe    eac-main-20261022
FEX bash        e42baddf6fbf43a8286a21dd9a3abcd68b617f77
```

RF 来源证据还包括 `/home/steamos/hd2-goal-rf-20261026/{configure.log,install-stage.log,trial-source-identity.json}`、保留源码和 `/home/steamos/hd2-rf-{pr20,core}.patch`。configure 记录 clang 19.1.7/aarch64/Release；identity 记录 `diskcache_format=36`、`StonkGuy/FEX PR20` 和 synthetic source SHA1 `e42baddf…`。该 identity 的 base 字段是记录原文，不能据它补造完整 Git 提交号。这里确认的是与历史 RF 产物的字节一致性及构建记录，**没有重新构建或验证每个二进制到完整源代码的可复现映射，不能证明 PR20 单独必要**。E2/E3；另见 [已有来源限制](FEX_CANDIDATE_PIPELINE.md)。

### 2.2 多套 FEX 与实际使用证据

磁盘同时保留 RF 安装目录、RF stage/源码/构建目录，以及 `Proton 11.0 (ARM64)` 和 `Proton Experimental (ARM64)` 中的 FEX 相关库。存在多个实现/副本，不等于多个同时生效。

- Steam `compat_log.txt` 在 **2026-11-15 23:27:50** 为 JE 注册的 command prefix 包含 `F/fex-compat-tool → R4/_v2-entry-point → JE/proton`；这是此次启动后的注册证据，**不是本次启动游戏的证据**。E2。
- `gameprocess_log.txt:7948` 和 `console_log.txt:12273–12274` 的 **2026-11-14 14:09:48** 记录明确使用上述 FEX 安装目录，而非 stage 或 App 候选目录；完整命令还指向 HD2 的 `start_protected_game.exe --bundle-dir data --release`。E2。
- 2026-10-26 的 `goal-rf-20261026/active-components.txt:3–5` 曾对安装与运行中 executable 核验到相同 `ce93cada…`。这是更早 FX 阶段的进程证据，不能替代 1.9.12 当前 `/proc/<pid>/exe`。E7。
- 本次未启动游戏，没有 1.9.12 正在运行的游戏 `/proc/exe`、`maps`、容器环境、FEXServer 路径采样。因此，**历史命令选择安装目录已证实，历史每一次会话的实际加载文件以及当前有效容器状态未确认**。

### 2.3 RootFS 注册、生成位置和 `/` 问题

实际 `F/emulator.json` 的相关内容：

```json
{
  "argv": "./usr/bin/FEX",
  "environment": {"FEX_PORTABLE": "1"},
  "container_argv": "./usr/bin/FEX",
  "container_environment": {"FEX_ROOTFS": ""},
  "main_argv": "./FEXCompatTool",
  "server_argv": "./usr/bin/FEXServerManager"
}
```

**空字符串和 `/` 不是相同的原始配置值。** 原盘的本次读取与 11-14 保留的离线记录一致。1.9.9 已修复测试盘 `steamos_test.img` 曾写 `/` 的记录，是第三套状态；不能套到本报告的 `steamos.img` 或未配置 `steamos-1.img`。旧 [1.9.9 报告](FEX_BASELINE_REPORT_20261115.md) 末段将“历史差异”简写为 `/`，应结合此次正式盘直接证据收窄解读，不把那一句当作原盘有效值的证明。

`F/ConfigTemplate.json` 使用 `RootFS: @FEX_ROOTFS_PATH@/`。实际脚本 `F/fex-compat-tool`：

1. 将 `FEX_PORTABLE=1`、`STEAM_COMPAT_MACHINE_ARCHITECTURE=aarch64-linux-gnu`、`STEAM_COMPAT_EMULATOR=F/emulator.json` 加入子进程环境。
2. `setup_rootfs()` 默认选择 `/usr/share/guestos/fex-mesa`；如果调用方已经给出 `STEAM_COMPAT_GRAPHICS_PROVIDER`，改取该 JSON 文件的父目录。
3. `personalize_config()` 读取模板，写入 `$STEAM_COMPAT_DATA_PATH/fex-emu/Config.json`；这是**现存脚本的行为说明，本次没有执行该脚本**。
4. 用 `F/usr/bin/FEX` 启动后续命令；临时 `FEX_APP_CONFIG` 可位于 `/tmp/fex-app-config-<pid>.json`，属于会话生成文件。

正式盘已生成的游戏配置位于：

`/home/steamos/.local/share/Steam/steamapps/compatdata/553850/fex-emu/Config.json`

mtime 为 **2026-11-14 14:09:49.630708 +08:00**，与上述历史启动相邻；内容为：

```json
{
  "Config": {
    "DiskCache": "1",
    "X87ReducedPrecision": "1",
    "RootFS": "/usr/share/guestos/fex-mesa/",
    "ThunkHostLibs": "/home/steamos/.local/share/Steam/steamapps/common/FEX-Emu//usr/lib/aarch64-linux-gnu/fex-emu/HostThunks",
    "ThunkGuestLibs": "/home/steamos/.local/share/Steam/steamapps/common/FEX-Emu//usr/share/fex-emu/GuestThunks",
    "ProfileStats": "1"
  }
}
```

`F/rootfs` 本次目录为空，脚本自身也说明使用系统 fex-mesa 时无需该目录。**空目录不等于缺少有效 RootFS；反之有目录也不证明能启动。** SSH 已核验 `/usr/share/guestos/fex-mesa/graphics_provider.json` 和 x86_64 loader 存在及其哈希（第 7.1 节）；整个 provider 的完整性及容器最终使用情况仍未确认。

另有 `/home/steamos/.config/fex-emu/Config.json`，RootFS 为 `/run/user/1000/nested_plasma/fexrootfs//`，mtime 2026-10-22；不能把这个桌面配置当成游戏配置。未检查到用户 `.bashrc`/`.bash_profile` 中设置 FEX_ROOTFS；用户 `environment.d` 不存在；A/B 两个 `/etc` overlay upper 的 `environment`、`environment.d`、`profile.d` 未见覆盖。检查范围不涵盖 Btrfs 下全部系统默认配置。

因此，跨重启可解释的链条是：**持久的安装目录/模板/Steam 映射被下一次 Steam 启动再次读取，启动脚本再次产生环境与每游戏配置**。不能声称环境变量本身在内存中跨重启保留。pressure-vessel 进入容器后，空字符串注册值如何覆盖前述配置、最终解析为何值，**未确认**；没有证据可回答“正式盘把 `/` 永久写在哪里”，也不应添加修复来使证据符合预期。

| 配置 / 集成文件 | SHA-256 |
| --- | --- |
| `/home/steamos/.local/share/Steam/steamapps/common/FEX-Emu/emulator.json` | `431e4340dabceb76fd83733864058e1d4176fa35aecde3b8c69cafc686968774` |
| `/home/steamos/.local/share/Steam/steamapps/common/FEX-Emu/ConfigTemplate.json` | `e458d3fe3d0e259de3465f621b6742df16e6f0858aa8484a39fd5e47366aeb1d` |
| `/home/steamos/.local/share/Steam/steamapps/common/FEX-Emu/fex-compat-tool` | `3dcb4a90765683c681d7d156ac52116317bbfea0d3161658664101510b0bc8d2` |
| `/home/steamos/.local/share/Steam/steamapps/common/FEX-Emu/unshare.py` | `bd68e7f2d51c1f1d605bed81c08c40c4c08534c4f05562cc9935491095eb26c8` |
| `/home/steamos/.local/share/Steam/steamapps/common/FEX-Emu/toolmanifest.vdf` | `35c57b914d1263ae03016aaca37784686c23503c80b7269a13f59f34fb97f08f` |
| `/home/steamos/.local/share/Steam/steamapps/compatdata/553850/fex-emu/Config.json` | `e1a3c864b70f5ee8fd819a66a2e6ac3f513b9115336310ce64e4c2a9f67487bb` |
| `/home/steamos/.config/fex-emu/Config.json` | `a5903b8b096aa12e52f402c274b49da9624850e330b73b033045a46a58d4b37f` |
| `/home/steamos/.config/fex-emu/app_config.json` | `41636f275cb333cb311823f11656e459c474bdaefc18ddfd3f3b16e57afc7c81` |


## 3. Proton

实际 JE 安装路径为 `JE`，version 内容 `1792806463 proton-je-11.0-20261014-3`。`S/config/config.vdf` 的 `CompatToolMapping` 保存：默认项 `0` 指向 JE（priority 75），游戏项 `553850` 也指向同一 JE（priority 250）。这证明**保存的默认/游戏选择**；11-14 的实际启动命令进一步确认那次使用了 JE。当前 Steam 内存状态未通过 API 再查。E2。

| 相对 JE 目录路径 / 归档 | 字节数 | SHA-256 |
| --- | --- | --- |
| `version` | 37 | `3ed3f9d71963b5f7ab305e33a295b5415982593333d9f7703ed31a6d1d4eb02b` |
| `proton` | 98152 | `4d8392f0ec4adebed83513589f4be30ad6a9c669230a94724a18dff0acdd203a` |
| `files/bin/wine` | 16872 | `01d81e68306a38b298531fdf09d750d376ccc8e12e409e540e178d94534429a8` |
| `files/lib/wine/x86_64-windows/ntdll.dll` | 1172469 | `a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe` |
| `toolmanifest.vdf` | 156 | `bb81d44a687cc6f4ea7ae05fa9f0502f35c48e462051809dce3b2a58492e3498` |
| `compatibilitytool.vdf` | 718 | `43a068c09d826c90c2a67147293a58b8289244cb34302cda89f19b8e6f0b0eaa` |
| `/home/steamos/proton-je-11.0-20261014-3.tar.xz` | 348245820 | `aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485` |


归档字节数/哈希与仓库 `native-app/Resources/proton-je-approved.json` 一致；该文件为 App 可使用的固定输入证据。本次只核验上述关键安装文件及保留归档，没有把所有已安装文件与归档逐一比较。`JE/user_settings.py` 不存在；其余生效变量见第 6 节 Steam 启动项。

其他在盘工具（存在不等于 HD2 使用）：

| 目录（相对 S） | version 文件内容 |
| --- | --- |
| `compatibilitytools.d/proton-je-11.0-20261027b-2` | `1793580311 proton-je-11.0-20261027b-2` |
| `compatibilitytools.d/GE-Proton11-11-x86_64` | `1792432585 GE-Proton11-11` |
| `steamapps/common/Proton 11.0` | `1791559474 proton-11.0-2e-x86_64` |
| `steamapps/common/Proton 11.0 (ARM64)` | `1791559733 proton-11.0-2e-arm64` |
| `steamapps/common/Proton Experimental (ARM64)` | `1793301884 experimental-11.0-20261027b-arm64` |
| `steamapps/common/Proton - Experimental` | `1794497090 experimental-11.0-20261112-x86_64` |
| `steamapps/common/Proton 10.0` | `1785139158 proton-10.0-4b` |
| `steamapps/common/Proton 9.0 (Beta)` | `1749140930 proton-9.0-4f` |

`compatibilitytools.d` 中还保留 GE 归档。不要把最新日期或 ARM64 标签当作实际所选工具。FX 历史统计将 Proton 简记为 `11.0-100`，不足以唯一映射安装包；本报告用 Steam 工具映射、启动命令及 JE version/hash 确定版本，不用统计简写覆盖它。

## 4. SteamLinuxRuntime

两套 Runtime 均存在：`R4` 与 `S/steamapps/common/SteamLinuxRuntime_4-arm64`，各自 `VERSIONS.txt` 均记 depot/runtime `4.0.20261021.265997`、pressure-vessel `0.20261007.0`。R4 额外带 `pressure-vessel-arm64`，版本相同。ARM64 目录还保留旧 `steamrt4_platform_4.0.20260928.262390` 目录；存在旧目录不表示使用旧版。E2。

JE 的 `toolmanifest.vdf` 中 `require_tool_appid=4183110`，R4 对应这个依赖；ARM64 Proton 的依赖是 `4185400`。11-14 的 HD2 启动命令明确使用 **R4**。11-15 Steam 注册的 JE 前缀仍相同。R4 目录有 pressure-vessel 容器准备的 `var/tmp-*` 文件树及 `bin/lib/etc` 等符号链接；其当前挂载命名空间、实际选择的 pressure-vessel 二进制和容器内 RootFS 未采样。

依赖链的直接证据为：Steam 游戏工具选择 JE → JE manifest 要求 4183110 → Steam 构造 FEX 包装 + R4 容器 + JE Proton + Windows 游戏命令。Runtime 提供容器环境，FEX 提供该链中的 x86 执行能力，Proton 提供 Wine/Windows 兼容层；三个路径都应验证，不能仅复制 FEX 主程序即称整套已就绪。

| 相对 Steam steamapps/common 路径 | 字节数 | SHA-256 |
| --- | --- | --- |
| `SteamLinuxRuntime_4/VERSIONS.txt` | 319 | `936cb7e1a2de6463e81b08443f3096ea6900de05d1723c0f0f7bcef946aad88a` |
| `SteamLinuxRuntime_4/_v2-entry-point` | 9257 | `ab9beb61c7c614caeb53e70ea0f4a1736d18b71eacb907ab09832db53cf6e46d` |
| `SteamLinuxRuntime_4/run` | 603 | `e9af67469db0c27d809dc2010f2fbe19651801cb1fef305ccc98b119207b422d` |
| `SteamLinuxRuntime_4/pressure-vessel/metadata/VERSION.txt` | 13 | `af269a693b159ceba091f98ea23a2689f0214b3a172a196dc8410410cb34b2f1` |
| `SteamLinuxRuntime_4/pressure-vessel/bin/pressure-vessel-wrap` | 880320 | `5357ec29b464961bfd1a743d4a28732d971062719933c9cbbea6ae95eb7110ad` |
| `SteamLinuxRuntime_4/pressure-vessel-arm64/bin/pressure-vessel-wrap` | 909104 | `0f08831d92b7747b113a967ba2eba2d3266c426ccd8854f872dc5130582e8079` |
| `SteamLinuxRuntime_4-arm64/VERSIONS.txt` | 281 | `4b276c11d1c52f8aa66357ddad627d6d19c327ae8dd1091969fb18be3ba3c985` |
| `SteamLinuxRuntime_4-arm64/_v2-entry-point` | 9257 | `ab9beb61c7c614caeb53e70ea0f4a1736d18b71eacb907ab09832db53cf6e46d` |
| `SteamLinuxRuntime_4-arm64/run` | 589 | `7962fc9132d51fe18a1480be8ad9786b9b0c228baffd167ab271d25989a826a9` |
| `SteamLinuxRuntime_4-arm64/pressure-vessel/metadata/VERSION.txt` | 13 | `af269a693b159ceba091f98ea23a2689f0214b3a172a196dc8410410cb34b2f1` |
| `SteamLinuxRuntime_4-arm64/pressure-vessel/bin/pressure-vessel-wrap` | 909104 | `0f08831d92b7747b113a967ba2eba2d3266c426ccd8854f872dc5130582e8079` |


这里是关键入口/版本文件哈希，不是完整 Runtime 树或官方 depot 的逐文件完整性认证。不能用 `VERSIONS.txt` 相同推断两个架构包相同。

## 5. 关键宿主文件与共同组件 SHA-256

以下相对路径基于 `/Applications/FX Steam Launcher.app`。所有文件只读取，没有运行 App 内命令。

| 相对 FX App 路径 | 字节数 | SHA-256 |
| --- | --- | --- |
| `Contents/MacOS/steamac-vm` | 10872016 | `b0de0c2e13582f922af58095c161f72d99ff92339ac2e33f5ad75580eb495cc5` |
| `Contents/Resources/gvproxy` | 25421264 | `1b5ede2fad119af225f12e1b24c772d310adf5435deab790bef7b9c2b7a0ebdd` |
| `Contents/Resources/Image` | 55789576 | `06b6c3a97e233fb6e7f84193d2b187b67ee88ada832c38fb6077b38cad68700a` |
| `Contents/Resources/initramfs.cpio.gz` | 3019073 | `68bfb9e3f3ec5e9a8af1ac1a09f58e33759a4b3e2bd513a88c62e957ae070ef9` |
| `Contents/Resources/steamac-layer.img` | 33943552 | `c099d2d227522766e5a3a5f82ed22393086db4aebbe93ca1d3a0e0d76c237b87` |
| `Contents/Frameworks/libvulkan_kosmickrisp.dylib` | 14830832 | `d92314d446fb302e91356b0be0cbb188c5e799a917c2435d6565608a2080ea62` |


两套环境均有 ARM64 Proton 的相关 FEX 库。正式盘本次哈希如下，与未配置 1.9.9 报告中记录的同路径文件相同：

| 相对 `S/steamapps/common/Proton 11.0 (ARM64)` 路径 | SHA-256 |
| --- | --- |
| `proton` | `a4f94c208355639c87877ba63e8faf1f26d8c0731db04f722dee66cdfcfbf478` |
| `files/lib/wine/aarch64-unix/libwow64fex.so` | `257041413ae02eb5e2ba31fd16d991478f3a3b53f8ed48b3cc356e42f77649be` |
| `files/lib/wine/aarch64-unix/libarm64ecfex.so` | `dc8f21f75ee11c3829b346d5a8d60ee87d24091f5e6ed901b5c36c739832ac53` |

它们的共同存在不能解释为何一个环境已经配置成功；也没有证据把它们认定为 JE 历史会话实际使用的 FEX。

## 6. HELLDIVERS 2 安装与历史运行

### 安装清单

| 项目 | 在盘实测 |
| --- | --- |
| AppID / 安装目录 | 553850；`S/steamapps/common/Helldivers 2` |
| Manifest | `S/steamapps/appmanifest_553850.acf` |
| StateFlags | `4` |
| buildid / TargetBuildID | `26568081` / `26568081` |
| Manifest SizeOnDisk | `25682918192` 字节 |
| 目录枚举总量 | 299 个普通文件，逻辑长度合计 `25737878112` 字节；非 `du` 分配块大小 |
| EXE | `S/steamapps/common/Helldivers 2/bin/helldivers2.exe`，28,743,256 字节 |
| EXE SHA-256 | `b434f6f326b7759978265f5863ef72e3c5edd4aa5315cc1ef4b640d204eae0bb` |
| 清单原文件 SHA-256 | `676a1811d926c79c4af1f8c94e8feef40923420868f9dc0958168f94e3a2bd9d`；账号字段未公开 |
| 库 | `libraryfolders.vdf` 只列默认库 `/home/steamos/.local/share/Steam` |

11-14 `content_log.txt:10792` 记录 8 个 depot、BuildID 26568081，之后为 Fully Installed/No Error。三个基础 depot 与 1.9.9 基线一致：553851/9093193760403568622、553853/6029796651416306804、553854/70283813008461964；正式盘另有五个可选 DLC depot（2506220、2506210、2506280、2506270、4199890）。安装目录大小不同不能直接视为兼容性原因，也不能用清单大小证明每个文件完好。本次未验证全套 depot。

### 保存的 Steam 启动参数

来源：`S/userdata/<account>/config/localconfig.vdf` 的 `apps/553850/LaunchOptions`（账号 ID 脱敏）。

```text
FEX_DISKCACHE=0 VKD3D_CONFIG=single_queue https_proxy=http://192.168.127.254:7890 FEX_NEEDSSECCOMP=1 WINEDEBUG=-all PROTON_USE_XALIA=0 PROTON_LOG=1 PROTON_LOG_DIR=/tmp taskset -c $(cat /sys/devices/system/cpu/online) %command%
```

11-14 实际启动日志中相同参数出现在命令前缀；它们在本次被当作文本读取，未执行命令替换。代理是该机器的既有网关/端口，不是通用部署值；参数中没有密码。`DiskCache=1` 模板与 `FEX_DISKCACHE=0` 启动环境属于不同配置层，不能只读模板就声称游戏用了磁盘缓存；本次未测最后解析结果。

### 多次成功使用的证据边界

用户确认 1.9.12 多次重启后正常运行。宿主 `game-stats.json` 的 553850 项保留 **13 条标为 launcher 1.9.12 的会话**，其中有 Vulkan 长会话，也有短 DXMT 试验，不能把全部当作成功。以下长会话提供独立的历史使用记录，不能单凭时长证明某个任务/EAC/多人成功。E5。

| 结束时间（Asia/Shanghai） | 运行秒数 | FX 记为游玩秒数 | 结束类型 | VM 配置内存 MiB |
| --- | --- | --- | --- | --- |
| 2026-11-08 18:50:04 | 6606 | 6584 | exit | 12288 |
| 2026-11-08 16:49:46 | 7375 | 7327 | shutdown | 10240 |
| 2026-11-07 23:35:30 | 10768 | 10750 | exit | 10240 |
| 2026-11-07 20:35:14 | 3682 | 3653 | exit | 10240 |
| 2026-11-07 00:59:14 | 7251 | 7228 | exit | 12288 |
| 2026-11-06 18:25:01 | 25952 | 25378 | exit | 12288 |


另有 **2026-11-14 14:11:07** 结束的 1.9.12/Vulkan 会话：run 83 秒、play 66 秒、窗口存在、统计 49.9 FPS；与 Guest 14:09:48 的 JE/R4/FEX 启动相邻。FX 的 FPS 是其记录值，不能当作本次基准测试。现有会话记录没有逐次 Guest boot ID/加载哈希，不能证明每一条都经历冷重启或每次组件完全相同。

本次没有游戏启动、EAC 测试、窗口操作或联网测试。10 月其他 FX 版本的多人成功记录保留为历史背景，不转写成 1.9.12 本次验证。

## 7. 跨重启持久化机制

| 调查项 | 结论 | 证据边界 |
| --- | --- | --- |
| FEX 实际部署目录 | `F`，七个 bin + FEXCompatTool + ConfigTemplate 与 RF stage 相同 | 在盘哈希；Steam 历史命令指向此目录 |
| 是否持久文件系统 | `findmnt` 实测 `/home` 为 `/dev/vda8` ext4 rw；FEX 和 Steam 实际路径属于该文件系统 | 与原镜像 GPT home 分区和 inode 分析一致；E2、E9 |
| FEX 目录符号链接 | 所查安装目录及九个 RF 文件为目录/普通文件，无 stage 替代链接 | 不代表全树无符号链接；Runtime/Steam 另有正常链接 |
| OverlayFS | 现场 `/` 为 Btrfs rw、`/home` ext4 rw、`/var` ext4 rw；`/etc` overlay rw、`/usr` overlay ro | `/etc` upper 在 `/newroot/var/lib/overlays/etc/upper`；`/usr` lower 含 FX layer；与 init 起始只读挂载不同，应以现场挂载状态为准。E9 |
| FEX 与 overlay 的关系 | RF 产物的实际路径及设备号属于独立 `/home`，不依赖写入只读 `/usr` layer | 已检查安装目录和九文件本身无 stage 替代符号链接；不代表全树无链接或游戏容器无 bind mount。E9 |
| Steam 自动加载 | `F/toolmanifest.vdf` + `emulator.json` 注册包装器；JE toolmanifest 依赖 R4；Steam VDF 保存选择 | 本次 Steam 启动日志重新形成对应 command prefix，支持“下次启动重新发现”机制 |
| RootFS 持久化 | 模板、wrapper、emulator.json 及 per-game Config.json 在 `/home` 持久保存；wrapper 每次启动重建子进程环境/配置 | 不是把环境变量永久留在内存；容器最终值未确认 |
| systemd 用户服务 | `steam.service` 正运行，加载 `/usr/lib/systemd/user/steam.service.d/50-steamac.conf`；启动前调用 FX 图形、Steam 客户端等脚本 | 当前进程环境及本次启动 journal 可见相应执行；不是 FEX 自动重部署证据。E9–E11 |
| 系统服务 | 已查 A/B `/etc` upper 及限定范围内 systemd/profile/cron、FX 脚本，未发现 FEX 自动恢复服务 | 扫描有限，不等于穷尽任意服务或脚本；SSH 由用户在首轮后重新打开。E9–E11 |
| FX 初始化 | App `initramfs.cpio.gz` 的 `init` 负责 A/B、overlay、SSH 开关和切换根 | 读取源码而未执行；已有启动日志确认选 B 与只读 layer |
| 自动恢复/重部署 FEX | **未发现已检查路径中的直接证据；完整机制未确认** | 保留构建目录不等于存在开机恢复任务；不能建议凭空新增服务 |
| 多次重启有效 | 用户确认；多日期 1.9.12 会话、持久文件与重新注册链相互支持 | 没有逐次冷启动身份/哈希，未实施重启实验 |

读取的 `init` 中关键语句位置：726–727 只读 Btrfs；773–777 var 与 `/etc` overlay；791–796 EROFS layer 与只读 `/usr` overlay；902–915 SSH runtime mask。脚本 SHA-256：`9db23a61489e3a978825e7c2112554159e7b501f48c87cb8e83dd01161e896b2`。这是 init 的初始挂载语句；现场 `/` 已为 rw，不能把初始状态当成当前状态。它揭示 FX 文件系统组织，不表示这些语句都是为 HELLDIVERS 2 特别修改的。

### 7.1 重开 SSH 后的启动机制和文件实测（2026-11-16）

`steam.service` 的 drop-in `/usr/lib/systemd/user/steam.service.d/50-steamac.conf` SHA-256 `f18fc2a1d47df8465fa64c9c6156b5bb5fd487bf7ebee12572b1ad95643be2a7`，设置 `VKD3D_DISABLE_EXTENSIONS=VK_KHR_shader_atomic_int64,VK_EXT_shader_image_atomic_int64`，并在 Steam 启动前调用 FX 的 `steam-client`、`steam-gfx-env`、`steam-gfx-path` 等。现场 Steam 环境有该扩展禁用值和 `MESA_LOADER_DRIVER_OVERRIDE=zink`；已存在的本次启动 journal 也记录图形环境初始化。仅静态读取脚本及既有日志，没有运行脚本或 `vulkaninfo`。这些是当前 Steam 进程证据，不能推断历史每次游戏容器都继承相同值。E9–E11。

`/usr/lib/steamac/steam-gfx-path` 的脚本内容显示：根据 Vulkan/DXMT 模式处理 Proton 目录中的 DXVK/VKD3D 图形文件，并保留/恢复相应备份；这属于 FX 的现有启动机制，**不是已发现的 RF FEX 恢复机制**。本次 JE 的四个图形 DLL 哈希均与仓库批准清单一致，具体见下表；这只覆盖四文件，不证明 JE 全树或此前每次启动的完整状态。`/home/steamos/.config/steamac/game-profiles.json` 与运行时副本当前均为空 games 表；其他可能的 FX 配置或历史值未穷尽。E10–E11。

当前 Steam 环境中 `STEAM_RUNTIME_LIBRARY_PATH` 值为 `No compat data path?`；已有启动 journal 记录从 FEX wrapper 取值时出现该文本。脚本检查显示此 wrapper 要求 compat data path。这里只记录现象及代码关联，不将其认定为失败原因，也未修改。当前未观察到 FEX、Wine、pressure-vessel 或游戏进程；游戏容器最终环境、挂载和加载映射仍未确认。

| 文件（JE 路径相对上文 JE） | SHA-256 | 证据 |
| --- | --- | --- |
| `/usr/share/guestos/fex-mesa/graphics_provider.json` | `ee9a8cdc6c19a194246c4e8695245ec84a72d85e5c907278a9c82a73cc44c8e7` | provider 描述 x86/x86_64 库目录，E9 |
| `/usr/share/guestos/fex-mesa/usr/lib/ld-linux-x86-64.so.2` | `85603f532debd89e06c59e819993924949c38f4e2fb4da2db897515a0a5f3687` | x86_64 loader 存在；不代表整树完整，E9 |
| `/usr/lib/libvulkan_virtio.so` | `f5d470a28384e0a05f2e6dad71c663edbe2f3180ee5194a7a7adf3be243622c9` | 现场 Steam 进程映射；内含 Mesa 26.3.0-devel 标识，E9–E10 |
| `files/lib/wine/dxvk/x86_64-windows/d3d11.dll` | `70d1993597a50f8f347009b23e94e915719db01d0a0ddfba573e1316b27eeb7a` | 与批准清单一致，E11 |
| `files/lib/wine/dxvk/x86_64-windows/dxgi.dll` | `b2c30079b15dc58d09b7998545ce74a9224e36ac548618dc2c170376b644fdba` | 与批准清单一致，E11 |
| `files/lib/wine/dxvk/x86_64-windows/d3d10core.dll` | `f4175e845a2cf37b140fbdd396914cdfe25a660279893456d656342d3aeaa091` | 与批准清单一致，E11 |
| `files/lib/wine/vkd3d-proton/x86_64-windows/d3d12.dll` | `8fd548a42b9d168b490e773ae162ab346b010866225b3e3b44e9f56268949b4f` | 与批准清单一致，E11 |

重启后的 SSH 采样再次核验九个安装 RF 文件、Steam 映射与参数、JE 关键文件、Runtime 版本/入口和游戏 EXE；第十个 `VERSIONS.txt` 在安装目录仍缺失。此时已是新的运行时观测，与用户提供的历史多次重启确认相互支持，但不替代逐次重启游戏验收。E11。

## 8. 命令、证据索引与未确认项

实际使用的主要只读命令/方法（均未触发游戏）：

```sh
ps -axo pid,ppid,command
lsof -nP -p 15613,15617,11593
lsof -nP /Volumes/Thunderbolt2TB/steamos.img
/tmp/hd2-offline-venv/bin/python -B /Volumes/Thunderbolt2TB/绝地潜兵脚本/审计资料/FX1912-readonly-20261115/inspect_disk.py
/tmp/hd2-offline-venv/bin/python -B /Volumes/Thunderbolt2TB/绝地潜兵脚本/审计资料/FX1912-readonly-20261115/inspect_disk.py --stopped
/tmp/hd2-offline-venv/bin/python -B /Volumes/Thunderbolt2TB/绝地潜兵脚本/审计资料/FX1912-readonly-20261115/supplement.py
```

SSH 补充阶段使用 `ssh -T` 复用严格校验的用户授权连接，通过标准输入运行 `python3 -I -B -`，只读取 `/proc`、`findmnt`、`systemctl show`、已有 journal、配置和文件哈希；未在 Guest 写入采集脚本。仅收集必要字段并脱敏，私有原始证据不入 Git。

`plistlib` 只取 App 版本/偏好中镜像与 SSH 等允许字段；`hashlib.sha256` 对文件流/提取字节计算哈希；`gzip` + CPIO 解析 App initramfs 内容，未运行其中的脚本。ext4 解析记录使用分区内 `/steamos/...`，本报告补上 Guest 挂载前缀 `/home`。初次采集脚本曾因库对象没有 `mode` 属性未保存部分哈希，修正采集代码后已重读；报告只采用成功结果。解析失败与缺失文件严格区分。

| 编号 | 来源 |
| --- | --- |
| E1 | Info.plist、初查 ps/lsof、`/Users/sunsan/Library/Logs/es.fxgam.steamac/steamac-vm.log`；最终宿主日志 SHA-256 `eb821a7948b90e4c42d02831c73d748a11fde74a49aadad23d56d2fc5f2b0e03`。11-15 会话从日志 5800 行开始，5852/5854 为 SteamOS/SSH 记录 |
| E2 | 原镜像 GPT/ext4 的两次只读采样：`disk-observation.json` 与 `disk-observation-stopped.json`；包含版本、哈希、脱敏 Steam 字段和日志摘录 |
| E3 | `supplement.json`：per-game RootFS、A/B `/etc` upper 目录、init/宿主组件、历史统计、采样时的只读文件句柄与 image stat |
| E4 | `elf-identities.json` 和 stage/安装目录逐文件 SHA-256；不执行二进制 |
| E5 | `/Users/sunsan/Library/Application Support/es.fxgam.steamac/game-stats.json`；原文件 SHA-256 `9ef5758724b344b74181706cebb924ceafbe64d7c6b4dad38571e12d99b43c56`，仅 553850/1.9.12 的必要字段经脱敏摘录 |
| E6 | `initramfs-selected.json`，来源 App `Contents/Resources/initramfs.cpio.gz`；没有从原盘提取敏感系统文件 |
| E7 | `/Volumes/Thunderbolt2TB/绝地潜兵脚本/HD2-StonkGuy-Fork-20261024/goal-rf-20261026/active-components.txt`，以及 [已有 11-14 审计](FX199_RF_REPAIR_20261114.md)、[历史基准](HD2_SUCCESSFUL_ENVIRONMENT_BASELINE.md)；均按各自时间和目标使用 |
| E8 | [1.9.9 原始报告](FEX_BASELINE_REPORT_20261115.md) SHA-256 `a7672ec23f15df780421a750753016dd3e747e20c86b619cd9cea72152490d79`；本次不改写它，也不拿当前已变化的 2223 环境补填原始空白 |
| E9 | `ssh-observation-20261116.json`：Guest 身份一致性、系统/挂载/进程及图形 provider 只读采样 |
| E10 | `ssh-startup-20261116.json`：Steam/FX 启动脚本、服务与图形文件静态采样 |
| E11 | `ssh-persistence-20261116.json`：重启后关键文件哈希、映射、进程与已存在 journal 采样 |
| E12 | `ssh-host-binding-20261116.json`：用户重新开启 SSH 后的 App、gvproxy、原镜像宿主绑定 |

本机采集目录：`/Volumes/Thunderbolt2TB/绝地潜兵脚本/审计资料/FX1912-readonly-20261115`。原始二进制、完整登录配置、镜像及私人日志不提交 Git；报告保留来源路径和已审核摘录供复核。

| 本机证据文件 | SHA-256 |
| --- | --- |
| `disk-observation.json` | `a504f2d8ec900ec1792808c816ec04df7c509eea2163b1104c179a3c6aafb567` |
| `disk-observation-stopped.json` | `3b0c282c313097f94678a76c8eab8f08f43157f797fe24e67887b853e525c082` |
| `supplement.json` | `93746242009f5b35d0739aa8116d66f59c1736954e8602fe4bcd19290a2b74fd` |
| `elf-identities.json` | `a0e44dd8a8e2441b7bf0a70fdda9a1e6e4d1d2d03a2da9e0942451b7c6697cb6` |
| `initramfs-selected.json` | `53af9f631e1e16e1aeac2c73fafd0e961467fdf564aaae35c20e3fa55821fbf6` |
| `inspect_disk.py` | `fe5299ef1f1367a4cb02fc210f1f0ac310357e76175dc5f411864f42fa90dcdc` |
| `supplement.py` | `0ade47602e6f70f79131525d92512acbc7f20ac2fc13d51b5ce5f86f2dc819a2` |
| `ssh-observation-20261116.json` | `4f343bf352ff7f78351b290a7bba36d0ea1156e29cd11832f357d80d35747e64` |
| `ssh-startup-20261116.json` | `01e7619b10bf8e799aea8aa18fa705e4f52587a4f1aef77fb9044a8959d6c5fb` |
| `ssh-persistence-20261116.json` | `c591b50512271a89a3db778fd2eda16cb0e8d39d053949534631c3bc4a085d66` |
| `ssh-host-binding-20261116.json` | `e1eb240d40ef65084ebe2326d3f08d344cd04f535b8b38c9b7b3e226c34475c2` |


**仍需另行验证：** 游戏实际 ICD/图形驱动详情、系统全局 FEX/FEXInterpreter 完整清单、provider/loader 全树完整性、游戏实际 `/proc/exe/maps/environ`、容器 FEX_ROOTFS 最终值及优先级、所有系统默认服务、完整 RF 可复现构建、全 Runtime/Proton 树完整性、逐项撤除因果实验及真实恢复。它们不妨碍记录本次观察，但阻止将这份记录升级为“最小自动部署方案已证明”。

本任务只新增环境文档，不改 App/本地化/UI，所以无需新 UI 资源、截图或 App 重构建。未有意修改 FX/Guest 组件或配置；正常 VM 活动及 SSH 登录可能写入镜像，未合并 main，未发布 Release；提交与远端状态以 Git 交付记录为准。
