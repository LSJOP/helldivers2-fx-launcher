# 性能配置菜单 / Performance profile menu

[README](../README.md) · [兼容性记录 / Compatibility](COMPATIBILITY.md)

## 简体中文

主菜单 `[2] 应用性能配置` 现在先打开浏览菜单。浏览和设备识别不要求 FX、SSH 或 Steam，也不写入设置。

```text
[2] 应用性能配置
 ├─ [1] M1 系列 → M1 / M1 Pro / M1 Max / M1 Ultra
 ├─ [2] M2 系列 → M2 / M2 Pro / M2 Max / M2 Ultra
 ├─ [3] M3 系列 → M3 / M3 Pro / M3 Max / M3 Ultra
 ├─ [4] M4 系列 → M4 / M4 Pro / M4 Max
 ├─ [5] M5 系列 → M5 / M5 Pro / M5 Max / M5 Ultra
 ├─ [6] 自动识别当前芯片
 ├─ [7] 查看当前性能配置
 └─ [0] 返回主菜单
```

芯片目录和配置注册表分离；列出硬件型号不表示该型号已经有配置或通过游戏验证。型号依据下方 Apple 官方资料核对。没有对应配置时显示“该芯片暂无性能配置”，不会为填充菜单创建参数。

当前仅保留原有配置：**M4 Pro／24 GiB，已验证（历史环境）**。参数直接读取 `performance_profile.SETTINGS`，没有复制新配置或更改其应用函数。验证范围来自[现有历史记录](COMPATIBILITY.md)，不扩展为所有 M4 Pro、GPU 档位或当前安装已验证；尚无实验性配置被加入生产数据。

选择该配置可以查看 CPU、VM 内存、Vulkan 驱动、Metal HUD 和 MetalFX 设置。只有只读检测的芯片和内存档位匹配时才显示应用入口；不会向其他芯片自动分配这组参数。应用前展示已保存值与目标值，默认取消；读取失败、确认后设置或设备变化时不应用。

用户明确确认后委托原有配置函数，因此仍会执行原依赖、SSH、备份与 Guest 安全检查。浏览菜单不能绕过受限模式。原 CLI `--configure` 继续保留原有明确调用方式；没有加入自动应用，也没有改动 `[1]` 的游戏启动链路。

“自动识别”只使用 macOS 原生只读命令：

- `sysctl -n machdep.cpu.brand_string`：芯片型号。
- `sysctl -n hw.memsize`：已识别 Apple Silicon 的统一内存字节数。
- `system_profiler -json SPDisplaysDataType`：只接受与当前芯片一致的单个内置 GPU 的明确核心数字段，不汇总外接 GPU、不推算型号最大值。

命令失败、超时、字段缺失或结果含糊显示“未知”。不提取序列号，不保存系统报告，不使用网络或第三方 Python 库。后续未收录型号可以显示原生识别结果，但不自动归入已有型号。

“查看当前性能配置”只读本机保存的五项 FX 偏好，不连接 Guest，不表示运行中 VM 已采用这些值。不存在的设置显示“未设置”，读取失败显示“未知”。CPU／内存等是否已在 VM 生效仍由原流程判断。

## English

`[2] Apply performance settings` opens a browse-first menu for M1–M5 families, native hardware detection, saved FX preferences and Back. Hardware membership and performance-profile data are maintained separately. A listed chip does not imply an available profile or verified game support.

Only the existing profile is retained, scoped to the historical **M4 Pro / 24 GiB** record. Its values come directly from `performance_profile.SETTINGS`. Historical validation does not establish every GPU variant or the current installation. Other chips show “No performance profile”; no experimental or invented presets were added.

Browsing is read-only and works in limited mode. The application action appears only when detected chip and memory match the record. A separate review shows saved and target values, defaults to Cancel, and blocks application on read failures or changed settings/device information. Explicit confirmation delegates to the unchanged profile application function, preserving dependency/SSH checks, backups and Guest safety. The existing explicit `--configure` CLI remains; game-launch code and resource parameters are unchanged.

Native `sysctl` reads the chip and memory; `system_profiler` supplies a GPU core count only for one matching built-in Apple GPU with an explicit count. Missing, failed, timed-out or ambiguous data stays Unknown. No serial numbers, saved system reports, network calls, external-GPU sums or model-based guesses are used. The current-settings view reads saved FX preferences, not live VM configuration.

## 型号来源 / Model sources

这是硬件目录的资料来源，不是游戏兼容性或性能预设验证依据。 / These sources establish hardware names, not game compatibility or profile validation.

- M1／Pro／Max／Ultra：[Apple M1 family and Ultra announcement](https://www.apple.com/newsroom/2022/03/apple-unveils-m1-ultra-the-worlds-most-powerful-chip-for-a-personal-computer/)。
- M2／Pro／Max：[Apple M2 Pro and Max](https://www.apple.com/au/newsroom/2023/01/apple-unveils-m2-pro-and-m2-max-next-generation-chips-for-next-level-workflows/)；Ultra：[Apple Mac Studio and Mac Pro](https://www.apple.com/newsroom/2023/06/apple-unveils-new-mac-studio-and-brings-apple-silicon-to-mac-pro/)。
- M3／Pro／Max：[Apple M3 family](https://www.apple.com/uk/newsroom/2023/10/apple-unveils-m3-m3-pro-and-m3-max-the-most-advanced-chips-for-a-personal-computer/)；Ultra：[Apple M3 Ultra](https://www.apple.com/newsroom/2025/03/apple-reveals-m3-ultra-taking-apple-silicon-to-a-new-extreme/)。
- M4／Pro／Max：[Apple M4 family](https://www.apple.com/newsroom/2024/10/apple-introduces-m4-pro-and-m4-max/)。
- M5：[Apple M5](https://www.apple.com/newsroom/2025/10/apple-unleashes-m5-the-next-big-leap-in-ai-performance-for-apple-silicon/)；Pro／Max：[Apple M5 Pro and Max](https://www.apple.com/uk/newsroom/2026/03/apple-debuts-m5-pro-and-m5-max-to-supercharge-the-most-demanding-pro-workflows/)；Ultra：[Apple M5 Ultra](https://www.apple.com/newsroom/2026/08/apple-introduces-m6-and-m5-ultra-for-a-big-leap-in-performance-and-ai-compute/)。

维护入口：`apple_silicon.py` 管理型号和原生检测，`performance_catalog.py` 管理范围与状态，`performance_browser.py` 复用 UI 2.0 的列表和键盘处理；三个文件均位于 `launcher-20261026/`。新增型号不会自动获得配置。
