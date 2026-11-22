# Dashboard UI V002 视觉精修报告

UI 与截图提交为 `834dec2b911f7baf3521061839a5a41ea24e1e49`，基于 `6c81b4f4e8ea309bf614c059315d6515ef8e51d2`。现有分支 `ui/motr7-artwork-20261114` 对应 [Draft PR #22](https://github.com/LSJOP/helldivers2-fx-launcher/pull/22)。本轮提交第二轮视觉审核。Debug 构建为 1.0.2（2026111501）。

## 界面和素材

| 区域 | 修改 |
| --- | --- |
| 主视觉 | 士兵原画保留，横幅由 260 缩至 214 点，淡化浅色渐变对人物的覆盖。 |
| 状态卡 | FX、Steam、EAC 和联机统一几何尺寸与证据样式。宽窗四列，窄窗两列。 |
| FX 控制 | 原生 SwiftUI Path 切角替代拉伸位图边框。重新扫描、手动定位和选择集中于 Dashboard。 |
| FX 实例 | 选中卡采用轻微暖色、细线和选中徽标。操作目标从当前选中候选派生，多实例另显示目标路径。 |
| 操作栏 | 启动、停止、重启使用统一高度和间距。停止和重启仍受正常退出后端限制。 |
| 侧栏 | 同一金色徽章适配深浅色。宽窗保留口号与条纹，窄窗保留徽章与条纹，六项导航仍可访问。 |
| 底部 | 使用方案 A 城市原画，等比裁切并在窄窗隐藏。 |

[设计 Tokens](design/Dashboard_UI_V002/UI_Design_Tokens.json) 记录双主题配色、交互表面、字号来源、圆角、边框和动画时长。布局和描边两种主题共享。总览按可用内容宽度调整状态卡、实例卡和按钮，侧栏在窄窗口切为 64 点紧凑模式。

两份新图均为用户批准的 AI 生成概念素材。城市替换应用中的二维剪影。未在本机找到所述徽章生成文件名，直接导入此次请求附带的 1774×887 透明 PNG，保留原始字节。三个参考图已归档，独立设计稿缺项见[素材及来源记录](design/Dashboard_UI_V002/README.md)。

## 删除和迁移的入口

- 移除总览的「更多」、独立「启动 Steam」、FX 版本管理 Sheet 和对应展示状态。删除 `FXManagerView.swift` 及其 Xcode 引用和旧面板的重复按钮。
- 首次运行的 FX 选择仍返回总览。内部 `.fx` 路由仍指向 Dashboard，供既有待选流程使用。
- 「运行环境」可展开 FX 详细信息与资源验证，包含目标路径、入口证据、资源哈希、兼容性以及只读旧版运行时检查。原有连接、环境探测、FX 状态检查和日志能力保留。
- Steam 服务和状态卡、游戏启动流程、现有安全确认和只读默认沿用原实现。

## 文件与截图

- 视图修改涉及 Dashboard、Sidebar、Content、Environment 和 FirstRunSetup。共享设计系统涉及 TacticalColors、TacticalComponents、TacticalTheme。
- 更新 `native-locales.json`、DEBUG fixture、截图工具、Xcode 源文件清单、两个资产图集、双语 README／Changelog、AGENTS、UI 规范、素材声明和截图清单。[完整文件列表](https://github.com/LSJOP/helldivers2-fx-launcher/commit/834dec2b911f7baf3521061839a5a41ea24e1e49)
- [23 张独立审核截图](images/reviews/dashboard-v002/README.md) 包括中英文深浅色宽窗、窄窗初始及滚动、诊断、确认、0 至 5 个实例、加载及切换 fixture。README 另更新 12 张截图。徽章有独立实拍细节，实机选中卡见宽窗，三按钮见滚动后窄窗，未选中卡见多实例 fixture。

## 构建与验证

- Xcode 27.2、Swift 6.4.2，arm64 Debug 成功。依赖使用与锁文件一致的 Sparkle 2.10.1。
- 完整 `native-app/script/run_checks.sh` 退出 0。FX 路径及选择 21 项通过。十语言各 600 个有效键，文档 15/15，12 张 README 截图路径、来源和哈希检查通过。
- 隔离 App 的实际可访问性操作验证了重新扫描、手动定位打开选择器并取消，以及启动 FX 出现原确认后按 Esc 关闭。实际启动、停止、重启均未执行。停止与重启在 UI 中为禁用。
- 当前主机只读发现一套 FX。多实例卡、相同名字和版本的路径识别、目标切换及加载展示使用明确标注的合成输入。中英文深浅色及两种宽度完成窗口检查。
- 拍摄后清理了 16 个无调用方的本地化键。清单分别保存捕获指纹与最终审核指纹，现有 UI 文案值一致。

## 未验证和 main 整合

真实 FX 启停与重启、Steam／游戏启动、SSH／Guest、EAC、联机、自动更新闭环和部署仍待实机验收。多实例切换没有真实多安装环境的验收结果。最终外观等待用户和 GPT 审核。

只读对照 main 为 `d293fd7dc8059902baf9bc9f591cf57892616f59`。PR 基线存在冲突。高重叠区域包括 AGENTS、双语 README／Changelog、截图、设计规范、总览、导航历史及本地化。另行获准后，在最新 main 基线上核对三方差异，保留签名、Update Helper、归档校验、更新配置、版本和发布说明，以及现有 FX／Guest／SSH／游戏启动业务，再移植 V002 视图和资产并重新验证。本轮 main 保持原样。
