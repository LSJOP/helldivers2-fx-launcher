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
- 此记录的 DXMT 验收来自独立工作副本。同盘两种模式自动切换、新用户 App 部署及异常回退需要各自的实机验收。已验证的原 DX12 工作流、成功基准和记录继续保留。

### 长期维护

FX、SteamOS、内核、FEX、Proton、DXMT、WMTR、驱动、音频或启动参数变更，以及 DX11/DX12 切换，先参照两套成功基准。新增实机通过的组合应增量记录版本、配置、实测结果、回归、回退方式、Git 提交和证据索引。保存历史验收和校验历史，使用仓库文档保留非敏感配置及指纹。
