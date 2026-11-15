# FX 1.9.9 未配置环境与 FX 1.9.12 历史成功环境对比

任务日期 2026-11-15；最终采样 2026-11-16（Asia/Shanghai）。依据 [1.9.9 原始基线](FEX_BASELINE_REPORT_20261115.md) 与 [1.9.12 只读检查报告](FEX_SUCCESS_ENVIRONMENT_REPORT_FX1912_20261115.md)；后者第 8 节给出来源、命令和证据文件 SHA-256。

**核心差异是额外部署并由 Steam 选择的 RF FEX + Proton-JE + Runtime 4 链，以及持久的注册/启动配置。不能把 FX 版本号差异、文件存在或历史成功直接推导为每个组件都必要。正式盘没有证实持久设置 `FEX_ROOTFS=/`；应先保留其空字符串注册及实际 per-game provider 配置，查明容器内生效值。**

## 1. 对比对象与证据口径

| 对象 | 绑定身份 | 使用的数据 |
| --- | --- | --- |
| FX 1.9.9 未配置环境 | `/Applications/FX Steam Launcher测试用.app`；`es.fxgam.steamtc`；`/Volumes/Thunderbolt2TB/steamos-1.img` | 11-15 原始报告及其“同日只读复查”；安装最终状态为 StateFlags 4。不是初次提交前 buildid 0 |
| FX 1.9.12 历史成功环境 | `/Applications/FX Steam Launcher.app`；`es.fxgam.steamac`；`/Volumes/Thunderbolt2TB/steamos.img`；inode 1734248 | 本次只读文件观测、11-14 实际启动日志、11-15 Steam 重新注册日志、历史 1.9.12 会话和用户确认 |
| 排除的第三套状态 | `steamos_test.img` | 11-14 经 RF/RootFS 修复的 1.9.9 测试盘，不是“新用户未配置”对照；不借用其 stock FEX 哈希填入 steamos-1.img |

正式盘初查在运行但 SSH 关闭，故没有向它建立连接或运行命令；其后 VM 已退出，再用只读文件句柄复查。没有启动/停止 VM、游戏、组件探针，未安装、清理或部署。只读检查并非对两个系统执行同一组现场探针，因此缺失字段均保持“未确认”。原始 1.9.9 基线 SHA-256：`a7672ec23f15df780421a750753016dd3e747e20c86b619cd9cea72152490d79`。

## 2. 对应字段比较

| 项目 | FX 1.9.9 未配置环境 | FX 1.9.12 历史成功环境 | 判断 |
| --- | --- | --- | --- |
| FX | 1.9.9 | 1.9.12，宿主日志构建 `7d9b6681c9` | 普通版本差异；未做只替换 FX 的对照 |
| 镜像大小 | 144,286,154,752 字节 | 453,523,800,064 字节 | 容量不同，不是兼容性证明 |
| SteamOS | 0.4.5，BUILD_ID 20261022.6150929 | 相同；本次启动选 rootfs-B | 没有证据要求升级 SteamOS |
| 内核/架构 | 实测 Linux 7.2.9-steamac、aarch64 | 启动 Image 内版本相同，ARM64；未现场 uname | 无已证实版本差异 |
| Guest CPU | 8 个逻辑 CPU | VM 分配 8；Guest 在线数量未实测 | 分配相同，口径不同 |
| 内存/Swap | Guest 约 11 GiB / 约 5.8 GiB swap | VM 分配 12,288 MiB；Guest MemTotal/Swap 未确认 | 不用配置量代替 Guest 实测 |
| Vulkan/GPU | 有 freedreno/virtio aarch64 ICD 与 fex-mesa x86/x86_64 ICD；实际设备/后端未确认 | 日志 Venus → KosmicKrisp/Vulkan；历史 M4 Pro/16 GPU cores；Guest ICD/驱动版本未确认 | 两侧证据覆盖不同，无法完整比对 |
| 独立 FEX-Emu | 默认库中没有此目录；PATH 无 FEX/FEXInterpreter | `S/steamapps/common/FEX-Emu/usr/bin/FEX`，已知 RF 哈希 | **关键候选差异**；不是证明只有该二进制决定成功 |
| FEX 版本/构建 | 内置库具体 FEX 源码/补丁未确认 | ELF `eac-main-20261022`；RF stage synthetic e42baddf…/format36；9 个安装文件一致 | 版本名不是完整构建出处 |
| RF 十文件 | 目录不存在，未部署该历史组 | 9 个安装文件匹配；VERSIONS.txt 只在 stage | 不能把第 10 个文件列为已安装或启动必要 |
| FEXBash | `/usr/bin/FEXBash` 631 字节脚本 | `F/usr/bin/FEXBash` 659,144 字节 ELF；系统 `/usr/bin/FEXBash` 未确认 | 不同路径/角色，不是一对一替换 |
| FEXInterpreter | PATH 未找到 | FEX 安装 bin 未见独立该文件；系统 PATH 未确认 | 不能断言系统完全不存在 |
| 多套 FEX | ARM64 Proton 内存在相关库 | 另有 RF 安装/stage/build 和 ARM64 Proton 库 | 必须检查实际选择，不能扫描到就算通过 |
| 实际 FEX 选择 | 未启动游戏，未确认 | 11-14 Steam 命令使用 RF 安装目录包装器；当前 /proc 实际映射未确认 | 历史运行命令比文件存在强，仍非当前加载证据 |
| RootFS 注册 | FEX-Emu/emulator.json 不存在；其余注册/实际路径未确认 | emulator.json：FEX_PORTABLE=1，container FEX_ROOTFS="" | 不能套用修复测试盘的 `/` |
| RootFS 模板 | 未确认 | ConfigTemplate RootFS=`@FEX_ROOTFS_PATH@/` | 可复现的配置生成输入 |
| per-game RootFS | 未确认 | compatdata/553850/fex-emu/Config.json：`/usr/share/guestos/fex-mesa/` | 关键路径证据；容器内最终值仍未知 |
| RootFS 文件/容器生效 | provider/注册/容器变量未确认 | `F/rootfs` 为空；脚本使用系统 provider；该 provider 完整性及容器值未确认 | 空目录不证明缺失；`/` 不可硬编码 |
| Proton-JE | 默认路径未见 compatibilitytools.d/JE | JE 11.0-20261014-3，在盘/映射/启动日志一致 | **关键候选差异** |
| 默认 Proton 选择 | 未找到 HD2 专用映射，默认选择未确认 | config.vdf 默认项0和553850均为 JE | 保存配置，不代替内存 API |
| ARM64 Proton | proton-11.0-2e-arm64 | 同版本、同脚本/两相关库哈希，另有实验版 | 共同组件，不能解释成功差异 |
| compatibilitytools.d | 默认路径没有 | JE 两版本与 GE-Proton 共存 | 只选择已证实版本；不能选“最新目录” |
| Runtime 目录 | SteamLinuxRuntime_4-arm64；非 ARM64 R4 状态未明确记录 | 两套均在，历史 JE 使用 SteamLinuxRuntime_4 | **关键架构/链路差异**，不能假定基线明确不存在 R4 |
| Runtime 版本 | 4.0.20261021.265997 | 两套同版本 | 普通版本号相同，架构与内容不等价 |
| pressure-vessel | 0.20261007.0 | 相同；R4另有arm64实现 | 版本相同不代表所有二进制相同 |
| Runtime 依赖 | 游戏实际选择未确认 | JE require_tool_appid=4183110；ARM64 Proton=4185400 | 需要完整工具依赖链 |
| Steam 参数 | 检查未输出游戏专用条目 | 保存 FEX_NEEDSSECCOMP=1、FEX_DISKCACHE=0、single_queue 等；历史命令一致 | 关键配置候选；不能说基线经证明绝对无参数 |
| 持久化 | Guest 未见 ~/.local/share/HD2FXLauncher；其他机制未确认 | /home ext4 文件 + Steam注册/映射 + wrapper每次生成环境；有系统 overlay但FEX不在/usr | 不要求新建 FEX 开机重部署服务 |
| systemd / 自动恢复 | 未调查 | 用户 override和/etc upper未见FEX恢复服务；系统默认服务未全查 | 缺乏证据，不是全局不存在的证明 |
| 游戏目录 | 默认库 Helldivers 2 | 相同逻辑路径，不同镜像 | 切勿交叉操作 |
| StateFlags/buildid/TargetBuildID | 同日复查 4 / 26568081 / 26568081 | 相同 | 初始 buildid=0 已被原报告同日复查取代 |
| EXE | 28,743,256 字节；b434f6f3… | 同大小/同 SHA-256 | 游戏 EXE 不是观测到的差异 |
| 安装目录大小 | Manifest 24,128,523,743；实测约23GiB | Manifest 25,682,918,192；299普通文件逻辑合计25,737,878,112 | 正式盘另有5个可选DLC；口径不同，非根因证明 |
| 历史游戏结果 | 未测试 | 用户确认跨多次重启成功；1.9.12 多日期长会话；11-14日志关联JE/R4/FEX | 本次未启动、未复测 EAC/单人/多人 |

这里 `S=/home/steamos/.local/share/Steam`、`F=S/steamapps/common/FEX-Emu`。每个“未确认”都是报告边界，不是安装/替换建议。

## 3. 文件及 SHA-256 对照

### RF 文件组

基线 1.9.9 默认库没有 `FEX-Emu`，故下表左侧对应文件均为“未配置目录中不存在”，**没有可填的旧哈希**。1.9.12 下表路径相对 `F`；详细 stage 路径见成功环境报告。

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


### 可直接比较的文件及配套差异

| 路径/角色 | 1.9.9 基线 SHA-256 | 1.9.12 SHA-256 | 解释 |
| --- | --- | --- | --- |
| 对应 FX App `Contents/MacOS/steamac-vm` | `be281f1d430d24b5147229f032fe44f9d3b25171ab7f2a560e792bfc9962cb99` | `b0de0c2e13582f922af58095c161f72d99ff92339ac2e33f5ad75580eb495cc5` | FX 版本不同；未独立证明影响 |
| `/usr/bin/FEXBash` | `8a907f46e455bf26d6bf2f2c09cf28e4aed6e2105a74c870a3d61c49b554e2d1` | 未采到同路径哈希 | 不拿 F/usr/bin/FEXBash 的 RF 哈希冒充此项 |
| `Proton 11.0 (ARM64)/proton` | `a4f94c208355639c87877ba63e8faf1f26d8c0731db04f722dee66cdfcfbf478` | `a4f94c208355639c87877ba63e8faf1f26d8c0731db04f722dee66cdfcfbf478` | 相同 |
| ARM64 Proton `files/lib/wine/aarch64-unix/libwow64fex.so` | `257041413ae02eb5e2ba31fd16d991478f3a3b53f8ed48b3cc356e42f77649be` | 相同 | 不能认定内置 FEX 库不同导致差异 |
| ARM64 Proton `files/lib/wine/aarch64-unix/libarm64ecfex.so` | `dc8f21f75ee11c3829b346d5a8d60ee87d24091f5e6ed901b5c36c739832ac53` | 相同 | 同上 |
| `Helldivers 2/bin/helldivers2.exe` | `b434f6f326b7759978265f5863ef72e3c5edd4aa5315cc1ef4b640d204eae0bb` | 相同 | 游戏主 EXE 相同 |
| `F/emulator.json` | F目录不存在 | `431e4340dabceb76fd83733864058e1d4176fa35aecde3b8c69cafc686968774` | 空字符串容器 RootFS 注册 |
| `F/fex-compat-tool` | F目录不存在 | `3dcb4a90765683c681d7d156ac52116317bbfea0d3161658664101510b0bc8d2` | 连接 Steam、provider、配置生成与FEX的集成脚本 |
| `compatdata/553850/fex-emu/Config.json` | 未采集 | `e1a3c864b70f5ee8fd819a66a2e6ac3f513b9115336310ce64e4c2a9f67487bb` | 与历史启动时间相邻的生成配置 |
| JE `proton` | JE未发现 | `4d8392f0ec4adebed83513589f4be30ad6a9c669230a94724a18dff0acdd203a` | 历史所选工具 |
| JE `files/bin/wine` | JE未发现 | `01d81e68306a38b298531fdf09d750d376ccc8e12e409e540e178d94534429a8` | 配套Wine关键文件 |
| JE `files/lib/wine/x86_64-windows/ntdll.dll` | JE未发现 | `a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe` | 同历史基准 |
| JE归档（348,245,820字节） | 未发现 | `aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485` | 完整保留归档哈希与App批准清单一致 |
| R4 `VERSIONS.txt` | 非ARM64 R4未明确记录 | `936cb7e1a2de6463e81b08443f3096ea6900de05d1723c0f0f7bcef946aad88a` | 版本/架构需同时核验 |
| R4-arm64 `VERSIONS.txt` | 版本已记录，哈希未采 | `4b276c11d1c52f8aa66357ddad627d6d19c327ae8dd1091969fb18be3ba3c985` | 不补造基线哈希 |
| R4 `pressure-vessel/bin/pressure-vessel-wrap` | 未采集 | `5357ec29b464961bfd1a743d4a28732d971062719933c9cbbea6ae95eb7110ad` | x86包入口 |
| R4 `pressure-vessel-arm64/bin/pressure-vessel-wrap` | 未采集 | `0f08831d92b7747b113a967ba2eba2d3266c426ccd8854f872dc5130582e8079` | 与正式R4-arm64的对应bin哈希相同 |

成功环境报告第 2/4/5 节另列工具注册、ConfigTemplate、Runtime入口及FX内核/initramfs/layer/图形库完整哈希；基线未采到对应值的项目不伪装成已完成二元比较。

## 4. 关键差异、普通差异与因果边界

**优先验证的关键候选**：独立 RF FEX 与配套包装器、Steam emulator 注册、系统 fex-mesa provider/loader、JE 11.0-20261014-3、4183110 Runtime 4、游戏工具映射、保存的 FEX/Proton 启动环境。这些构成直接可追踪的历史启动链，适合作为隔离复现输入。

**普通差异或证据不足**：FX 版本/可执行文件、磁盘容量、DLC/目录大小、其他未选 Proton、内存分配、日志开关。没有只改这些因素的对照，不能列为成功必要条件。SteamOS build、游戏 EXE、ARM64 Proton 脚本与两库相同，反而说明不能仅通过升级它们解释成功。

**需要更正的假设**：正式盘没有验证 `FEX_ROOTFS=/`。可确认的是 emulator 的空字符串、provider 模板和生成配置；测试盘的 `/` 是另一状态。不要仅凭错误文本“RootFS”或旧报告概述作全局修改。容器内 `/` 可能表达与外层不同的命名空间，但本次没有采到该实际值，不能作为事实。

**RF 与最小集合**：已有 [11-14 修复记录](FX199_RF_REPAIR_20261114.md) 是对第三套测试环境的整组替换，不能隔离 PR20 或十文件中某一项的必要性。本次观察到安装目录没有 VERSIONS.txt 仍有历史运行记录，更不能强行把该元数据文件视为运行依赖。RF 产物与源代码的可复现绑定仍受 [来源审查](FEX_CANDIDATE_PIPELINE.md) 限制。

## 5. HD2FXNative 自动部署建议

以下均为**建议，未执行部署或恢复**。“可直接复现”表示有确定输入/落盘位置可编排，不表示当前 App 已完成全新环境或跨重启验收。代码参照本任务起点 `76e6367fd3a251628aec36071764cff50b9e485e`；本次不改产品能力。

### 5.1 组件包装与来源

1. **内置 App 的小型内容**：版本/架构/哈希清单、目标身份校验、Steam VDF语义编辑规则、emulator/模板 schema、只读证据采集逻辑、事务回执/恢复逻辑。优先复用现有 `successful-environment-baseline-v1.json`、`proton-je-approved.json` 和服务层；旧基准中的 FX1.9.4 标识不能静默改成1.9.12。包装器和 RF 二进制只有在完整来源审查后才可随包分发；不能从私人成功盘直接拷入生产 App 当作已批准依赖。
2. **联网获取的大型内容**：固定 JE 归档（348,245,820 字节、上表 SHA-256）；对应架构 Runtime 4（4183110）及 Steam 所需官方依赖，优先由 Steam 正常取得。不要打包整块镜像、登录数据、compatdata/prefix、个人缓存或游戏。RootFS/provider 是否缺失必须先验证，暂无证据要求下载一个任意 FEX RootFS 替换系统 provider。
3. **SSH/SFTP 上传内容**：未来可上传已审核包到 Guest 专属 staging 目录、所需小型事务脚本/配置及回执；核对后再切换。RF 组需要包含可工作的 Steam 集成及完整依赖，不能只上传 `usr/bin/FEX`；安装目录和 stage 差异须明确声明。JE 可由 Guest 安全下载或宿主下载后上传，同一固定哈希验证。不得上传密码、token、Steam账号文件或复制历史 prefix。

固定 JE 下载地址已经在仓库批准清单内；本次未下载。Runtime 的官方安装渠道及4183110身份可参见 [Valve Steam Runtime说明](https://github.com/ValveSoftware/steam-runtime/blob/master/README.md#installation)。该来源只支持获得Runtime的渠道，不证明历史固定版本仍可直接取得；精确 depot/manifest 与完整文件校验仍须在未来准备包时核对。

### 5.2 每项操作、验证与恢复

所有未来变更先绑定 FX/App、镜像、SSH目标、Guest身份/boot与配置revision，并确认Steam/游戏的适当状态。恢复前比较“当前=本次安装后的预期值、备份=原值”，外部漂移时停止覆盖；保留两边供人工处理。此规则是后续部署方案，本次未运行。

| 操作 | 可由 App 复现程度 / 所需输入 | 验证方法 | 恢复方法 |
| --- | --- | --- | --- |
| 1. 目标及只读检测 | 可直接编排；按路径、bundle、镜像打开者、Guest身份区分正式与测试 | 记录目标/boot、目录类型、文件hash、Steam注册；不把存在判为ready | 纯读无环境恢复动作；凭据只走已有受控会话 |
| 2. RF FEX 部署 | **需进一步验证/批准**；9个安装hash已知，完整产物来源、依赖和与第10个元数据的关系未完成 | 全树hash/mode/link、架构、wrapper/注册、provider/loader；之后在隔离盘验证实际容器与进程 | Steam/游戏停止后保留原FEX整树；带回执原子切换；仅在前后hash一致时换回，不删未知文件 |
| 3. Steam FEX 集成文件 | 路径/内容可直接描述；迁移到新版FX需验证兼容性 | emulator argv/main/server安全解析；toolmanifest；Steam重启后prefix确实包含该安装目录 | 恢复本次所改的精确文件和模式/链接；不要全局重写Steam配置 |
| 4. SteamOS系统配置 | **没有证据支持为复刻RF而修改只读/usr、initramfs、系统更新或新增服务**；只检查provider与现有集成 | 在隔离实例读取mountinfo、provider JSON与x86 loader、用户/系统服务 | 此方案默认不写系统层；若将来确有变更，必须另建针对该路径的备份/回执，禁止重建原镜像充当回滚 |
| 5. RootFS参数 | 保留目标原注册；外层provider、模板和compatdata生成方式已知；**不通用写FEX_ROOTFS=/** | 采样外层和容器内FEX_ROOTFS/FEX_PORTABLE、有效Config、loader路径及实际maps；环境值/挂载namespace需关联同一运行 | 恢复原emulator/模板及本次生成配置的前值；保留用户自定义provider，不能把全局Config覆盖成历史旧值 |
| 6. JE下载/安装 | 固定11.0-20261014-3归档输入与App批准清单一致；可复用固定包安装流程，实机恢复待验证 | HTTPS来源/归档长度SHA-256、安全解包、完整文件清单、版本/关键Winehash；受控探针与游戏验收分开 | 独立版本目录安装；保留原版本与工具映射；回滚只撤销本任务拥有且未漂移的安装，不能移走其他工具 |
| 7. 游戏Proton选择 | 可直接复现553850→JE；**不必把全局默认0也改成JE** | Steam保存后读回游戏映射；下次实际command prefix与日志确认使用JE | 恢复553850原工具选择（包括原先不存在的情况），不影响其他游戏 |
| 8. Runtime4安装 | 需要4183110及对应架构/版本；精确4.0.20261021.265997分发包仍需固定完整manifest | Steam安装状态/depots、VERSIONS、pressure-vessel0.20261007.0、入口与完整树；JE依赖链 | 保留原工具/旧依赖；先恢复游戏映射，不删除其他游戏共用Runtime；若使用受管并列目录，校验回执后恢复旧指向 |
| 9. 游戏启动参数 | 可语义合并已知FEX_NEEDSSECCOMP=1/FEX_DISKCACHE=0；single_queue等先作为待验证profile；代理/CPU按目标解析 | 保存前后VDF/API读回；运行时实际环境/CPU允许集；保留用户参数、%command%和引号语义 | 精确恢复原LaunchOptions；检测用户后续修改，不能覆盖；不复制历史网关、日志路径作必需值 |
| 10. 跨重启机制 | 复刻/home持久文件+Steam注册+wrapper每次生成配置；**没有依据新增FEX开机恢复/重部署服务** | 隔离盘部署后多次正常重启，每次记录hash/boot/配置/实际FEX&JE&R4；不运行App也检查Steam能否重读链 | 恢复原树/注册/工具选择及本次配置；不触动既有系统服务；恢复后再做相同冷启动验收 |

### 5.3 自动化边界与后续验证顺序

- **有固定输入可复现**：JE版本与归档校验、553850工具映射、Steam参数语义编辑、持久目录与注册清单、逐文件备份/读回。当前代码 `ComponentDeploymentAdapters.swift` 已区分FEX文件预检与能力探针，且明确provider存在不是容器配置证明；这份报告不授权执行会写临时文件的探针。
- **暂不能直接放行**：RF完整可分发/可复现产物、空字符串与`/`的容器语义、系统provider完整性、Runtime精确包、未采样的系统默认服务与跨重启进程证据。不能放宽hash门禁来匹配某次不同构建输出。
- **先在独立、可恢复的测试镜像中验证**：冻结官方基线→只补全所需工具链→确认实际FEX/JE/Runtime与RootFS→多次正常重启→逐项撤除/替换以判断必要性→恢复原状态并验证。EAC加载、游戏画面/操作、任务、多人分别记录。实际执行需要后续任务授权，本次未做。
- **不应自动复制**：SSH/Steam密码或token、用户prefix与账号目录、历史代理地址、旧机器CPU约束、缓存、其他游戏设置、系统更新、只读/usr层或原始成功镜像。容量、DLC与其他未选Proton的差异没有部署依据。

两份报告属于只读审计文档；没有把观察结果转成部署、修复、Release或main合并。UI/本地化未变，不需要新截图或App重构建。
