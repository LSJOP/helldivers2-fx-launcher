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

## DX11 + DXMT 已验证成功环境 · 2026-11-28

| 层级 | 成功配置与证据 |
| --- | --- |
| 宿主 | Apple M4 Pro，24 GB 统一内存，macOS 27.2.1（26B131）。FX 1.9.15，上游构建 `862e991347`，官方 Developer ID `V25VKGTW55`（FX GAMES FZ LLC），严格签名验证通过。8 vCPU、12,288 MiB Guest RAM，1280×800 验证窗口；该分辨率只描述测试条件。 |
| Guest | SteamOS 0.4.5，Build `20261022.6150929`，既有工作副本，内核 `7.2.9-steamac`，aarch64。Steam 管理的 x86_64 Runtime `4.0.20261021.265997`（depot AppID 4183110，Build 26116036）。游戏 AppID 553850，Steam Build 26568081，菜单 `release/01.007.203/19543`。 |
| 转译 | 公布来源见[组件清单](ENVIRONMENT_COMPONENT_MANIFEST.md)。原 RF FEX `eac-main-20261022`，基准可执行文件指纹见上表。x86_64 Proton-JE `11.0-20261014-3` 的原始归档及 ntdll 指纹见上表，测试工具名为 `proton-je-11.0-20261014-3-dxmt-local`。 |
| D3D11 | FX 内置 DXMT，上游基线 `e94c312f5c054263acf261cfa109edf13e757587`，FX 补丁基线 `17896accb64afa6b06bf1bdbc6183f6d00a35667`，Guest 载荷标记 `8ae333465a742e5c`。实际建立 D3D11 FL12_1，`winemetal` 与宿主 WMTR 活跃，Metal 呈现回调有持续进度。 |
| WMTR 与生效的 Guest DLL | `libwmtr_host.dylib` SHA-256 `8aadb3969286411b035278ac748c2ad177d3323267b4cd0e1f323bc7e61fc92b`。测试 prefix 的 x64 `d3d11.dll` SHA-256 `139a2752b29240ee549cb124f26cc0dd26f7e8e5db79b75df01025b8c89d528b`，`winemetal.dll` SHA-256 `6d6c5bea44c3350566c01e49cc744e47b7a303396bbc5d8c144600078b63ae28`。 |
| 策略 | 在独立 FX 偏好域启用实验性 DXMT，为 AppID 553850 选择 DXMT。保留独立 x86_64 兼容工具和 prefix。关闭宿主目录共享，保持 macOS 安全设置及游戏官方启动流程。FX 管理 DXMT、WMTR、KosmicKrisp；Steam 管理游戏和 Runtime。 |

[FX 官方版本和签名说明](https://github.com/fxgl/steamac/releases/tag/v1.9.15) · [DXMT 源码固定版本](https://github.com/fxgl/steamac/blob/v1.9.15/host/dxmt/pin.env)

### 复现与回退

1. 选用受信任的隔离 Guest。沿用已有游戏、原 RF FEX、Steam Runtime 与可信 Proton-JE 归档。使用独立 FX 偏好域（已验证实例为 `es.fxgam.steamac.hd2dx11`），先退出同机正在运行的 FX。
2. 保留原 DX12 工具与 AppID 553850 prefix 的完整目录和映射，活动路径仅放测试工具及启动用独立 prefix。FX 1.9.15 的图形切换脚本在工具目录内切换 DLL，并标记工具与 prefix。可写共享链接会有污染风险。初始验证用独立工具副本，部署时可试用文件系统写时复制并保留安全回退。
3. 配置 AppID 553850 的兼容工具为 `proton-je-11.0-20261014-3-dxmt-local`，独立图形后端为 DXMT。以下路径参数来自本机成功挂载布局，机器迁移时解析各自的实际位置：

```sh
open -a "$FX_APP" --env STEAMAC_DEFAULTS_DOMAIN=es.fxgam.steamac.hd2dx11 \
  --env WMTR_DRAWABLES=3 --args --disk "$TEST_DISK" \
  --disk "$FX_APP/Contents/Resources/steamac-layer.img:ro" \
  --cpus 8 --mem 12288 --display 1280x800 --no-share --ssh-port 2222 \
  --vulkan-driver kosmickrisp --wmtr-lib "$FX_APP/Contents/Frameworks/libwmtr_host.dylib"
```

实测 Steam 参数如下。按实际 Guest 路径解析 `RF_EMULATOR_JSON` 和 `PROTON_LOG_DIRECTORY`。详细 Metal 诊断可按需在宿主启用 `WMTR_PRESENT_TRACE=1`，日常运行只需设置 drawable 数。

```sh
FEX_DISKCACHE=0 FEX_NEEDSSECCOMP=1 PRESSURE_VESSEL_EMULATOR=<RF_EMULATOR_JSON> PROTON_USE_XALIA=0 VKD3D_CONFIG=single_queue PROTON_LOG=1 PROTON_LOG_DIR=<PROTON_LOG_DIRECTORY> %command% --use-d3d11
```

4. SteamOS 图形用户会话中列出 `pactl list cards short` 与 `pactl list cards`，对实际 VirtIO 卡应用 `pactl set-card-profile <card> output:stereo-fallback`，确认仅剩播放源及 monitor。在隔离 prefix 将游戏抗锯齿关闭，使用原始渲染比例并保留其余用户画质。麦克风未使用时关闭游戏语音，避免把回放 monitor 作为输入。FX 音频保持开启。
5. 启动游戏后在驱动提示选择「继续」，确认游戏命令行、DXMT、FL12_1、Metal 实际呈现、舰桥移动、菜单与声音。日志和截图仍保存在原专项报告旁。
6. 日常 DX12 使用原 FX 偏好域及原磁盘。若需要同一测试磁盘回退，先退出游戏、停止 Steam，按目录对调恢复已保存的原 prefix 和原 JE，并恢复 AppID 553850 原映射/参数、FX 图形与共享设置和 Guest 声卡模式。专用 DX11 工具和配置可移入私有备用目录。保留整个 prefix 内容、用户存档和其它 Steam VDF 条目。复核原 prefix 元数据及工具文件指纹，完成后再启动 FX/Steam。

### 验收索引和限界

- 专项报告 `FX1915_HELLDIVERS2_DX11_TEST_20261127.zh-CN.md`。相关本地证据树为 `FX1915_HELLDIVERS2_DX11_EVIDENCE_20261127`。其 `followup/SHA256SUMS.txt` 的 SHA-256 为 `3891a1a4e6e556c70ca0d4c38ca786117b4d1089096d6ba83570b5606df7b875`。索引含 `dxmt-accepted-renderer.txt`、舰桥移动前后和菜单实拍。
- `audio/SHA256SUMS.txt` 的 SHA-256 为 `0c88e8e14e2108d4760d6ce3f4ba381a7abea02f9c8948d138f24d19748ac664`。索引含 `dxmt-output-only.txt`（CoreAudio、PipeWire、宿主应用音频振幅、游戏 D3D11）、`dxmt-virtual-capture.txt`（BlackHole 997 Hz 下行采集和游戏录音绑定）和两组游戏 HUD 性能截屏。游戏截图及原始文件保留在本地证据目录。
- 同机同舰桥视角，1280×800、原始渲染比例、TAA 关的五个游戏 HUD 样本中位数为 DXMT 98 FPS、DX12 42 FPS。DXMT 的宿主 Metal 回调样本另为 98.23/s。两组音频模式不同，宿主 swap 约 15.8 和 25.3 GiB，结果仅限该短测。
- 已知限制包括 TAA 开启时网格伪影，禁用即可规避；带音频停帧和采集超时存在时间关联，底层原因待定位；实体麦克风、游戏内语音传输、多人及战斗尚未验收。FX DXMT 扩大可信 Guest 对宿主的访问面。GE-Proton x86_64 在图形初始化前退出，DXVK/Venus/KosmicKrisp 仍有提交超时。
- 上述 DXMT 音频、性能和呈现诊断来自独立工作副本。App 同盘验收单独记录在下方。原 DX12 工作流及其历史成功记录继续保留。

### Native App 同盘验收 · 2026-11-28

在既有的独立测试盘完成 App 双向切换。关闭 DX11 后，同一块盘启动到 Vulkan，恢复原 Proton-JE 映射、启动参数、声音和 DX12 prefix。启动参数、prefix 版本元数据和原画质文件经核对。游戏加载 VKD3D-Proton 3.1.0、Wine Vulkan 和 Venus/KosmicKrisp，进入舰桥并可移动。重新启用后，隔离 Proton、DX11 prefix、DX12 prefix 与 Steam 管理的 Runtime 均有相同文件系统和 inode 证据。DX11 游戏实际加载官方 DXMT/WineMetal，初始化 FL12_1，舰桥移动及菜单通过，FX 声音采样 RMS 约 0.03294。

FX 的 DXMT 安装逻辑修改兼容工具与 prefix 内的 DLL。App 对原 JE 保持独立，使用只指向已知隔离目录的 FX 服务范围。Guest 当次实际分配约 1.96 GiB，覆盖隔离 Proton 和 DX11 prefix。重启后在游戏启动前重新检查仅输出和 monitor 静音，保留原 DX12 音频记录。DX11 采用独立 FX 偏好域和关闭宿主目录共享的设置。游戏运行期间请求恢复时，App 保留当前虚拟机和 prefix，退出测试游戏后重试成功。还验证了重复启动按钮保护、撤销初次授权、在写入前取消活动配置，以及从已关闭 App 和 FX 的持久化收据继续恢复。

候选来源为 `dev/core`。核心实机使用 `a39f377c56096acfded0e5bfd3e5b83d352acab2`，后续 `db9f789bb3f79363b9035323911f079f84062e28` 保留已有启动结果，同时在总览显示图形模式。版本均为 `1.0.8 (2026112703)`。候选包为本机 ad hoc 签名 arm64 构建，批准的 RF FEX 和 Proton-JE 载荷校验通过。技术日志、运行证据和中英文实拍保存在原专项报告旁。

最终构建在已有 FX、SteamOS 和游戏、无活动 DXMT 配置及缓存的测试盘通过首次配置。App 创建了新的 DXMT 工具和 prefix，并从总览启动到舰桥。原 DX12 prefix 和 Steam Runtime 的 inode 未变。DXMT FL12_1、角色移动与宿主声音已验证，宿主应用输出 RMS 约 0.03642。验证期间出现一次本地 SSH 转发端口占用，重试后通过。游戏仍可能显示驱动版本提示，测试中从游戏窗口选择继续。实体麦克风、游戏内语音、联机与其它 FX 版本未纳入本次 App 验收。

本地证据目录中，`app/SHA256SUMS.txt` SHA-256 为 `b0c14de8bfa25c625eddf5835a1377a00cdd6b46eef5b153a545e78db724b3c3`。初次交接的 `handoff/SHA256SUMS.txt` SHA-256 为 `cb2d81ed81a07961fc96370a0a1a000b13cf404d65e6660c190123ccadb58dea`。最终候选可执行文件 SHA-256 为 `fad9b4b99b0527967af0e788b4e0b3c1f7025131435f286df1982b55d9d5d437`。

### v1.1.0 Stable 发布基线

正式构建 `2026112801` 继承 `dev/core` 提交 `5886b11a1c4f76d8adc3ce814931a8e755cca099` 的 FX 1.9.15 舰桥、声音、首次配置、同盘切换与 DX12 恢复实机证据。发布源码保留 DX12 为默认。首次配置中的隔离 SSH 连接改用系统分配的转发端口，遇到本地绑定冲突时在同一已验证 FX 目标上重试一次。发布阶段复用历史游戏证据，不再次启动 FX。

FX 1.9.12 的历史 DX12 环境另有只读归档。FX 1.9.15 的 DX12 实测使用原 Proton-JE、VKD3D-Proton 3.1.0 和 Venus/KosmicKrisp。启用 DX11 后恢复 DX12 的步骤是退出游戏，再关闭游戏性能配置中的 DX11 开关或选择「恢复 DX12」。[FX 1.9.12 历史成功环境](FEX_SUCCESS_ENVIRONMENT_REPORT_FX1912_20261115.md) · [中英文界面证据](../images/README.md) · [v1.1.0 更新日志](../../CHANGELOG.zh-CN.md#v110--2026-11-28)

### v1.1.1 专项接续 · 2026-11-29

当前用户报告在 FX 1.9.15、v1.1.0 下可播放动画，动画结束无法进入舰桥。缺少故障端诊断报告。历史成功属于上面的已验收版本和具体测试盘。正式构建未改动 DX11 Guest worker，继承 `5886b11`，并增加隔离 SSH 转发重试。候选检查 Steam 就绪后的 TAA、输出 profile、monitor 静音及实际 WMTR 参数，按 Prefix 交接最新配置，恢复仅改 TAA 和已管理的兼容配置。渲染比例、分辨率及画质由用户决定。候选结果以当前实机、配置字段对比和诊断证据为准。

最小反馈包括 Mac 型号、内存、系统版本、日志页复制的诊断报告、同机 DX12 是否进入舰桥、DX11 的具体表现（黑屏、停帧、持续加载、无响应、退出或连接错误）以及是否还有声音。

候选实测使用独立测试盘及端口 22465。Release `2026112901` 核验缺密码在总览内显示「Go to Settings」，同一设置页完成真实 SteamOS SSH 密码挑战并保存一条受目标约束的加密记录。首页复用该凭据启动，FX 实拍到开场。00:58 主机重启，舰桥、角色操控和声音缺少本次实证，重启原因未确认。重启后的 FX 进程使用默认端口 2222 与发行版 gvproxy，未接管。旧候选的 DX11 sudo 诊断实测被 Guest 身份检查拒绝，后续修复仅允许已通过 FX、磁盘和 Guest 机器身份检查的 DX11 收据。修复后的实机路径待复验。

同一就绪 DX12 流程的源码调用对照中，旧版依次建立诊断 SSH master、首次检测 master、完整复验 master，共三次，新版一次检测可将已验证的 master 用于后续启动。存在健康 master 时也可复用。无部署时完整环境检测由两次降至一次，或使用仍有效的同启动周期结果。实机 A/B 次数、sudo 次数和耗时尚未完成同任务测量。首次部署的写前校验和变更后复验继续执行。

**FX 音频反馈草稿。** FX 1.9.15 Build `862e991347`，M4 Pro、24 GB、SteamOS 0.4.5、同盘同 Proton-JE、WMTR DRAWABLES 3、TAA 关。历史会话先出现 `capture start exceeded 200 ms`，约 2.7 秒后帧进度停止。仅立体声输出且播放 Monitor 静音时已观察到舰桥和持续游戏声音。BlackHole 的 997 Hz 虚拟信号打通了 CoreAudio 到 Guest 的采集链，并分别观察到游戏绑定录音流。实体麦克风、帧稳定性和语音传输仍待实际对照。请对照 FX 原生实体输入和仅输出两种条件，关联 PCM start/cancel、回调线程及最后可呈现帧，检查超时回调清理是否影响后续帧推进。该方向待证实，草稿待项目负责人审核。

### 长期维护

FX、SteamOS、内核、FEX、Proton、DXMT、WMTR、驱动、音频或启动参数变更，以及 DX11/DX12 切换，先参照两套成功基准。新增实机通过的组合应增量记录版本、配置、实测结果、回归、回退方式、Git 提交和证据索引。保存历史验收和校验历史，使用仓库文档保留非敏感配置及指纹。
