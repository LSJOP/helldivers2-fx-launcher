# Dashboard UI V003 最终整合报告

V003 独立 UI 提交为 `735b55e5b80e3f5cf56716ad90e216f78dff1a4b`。整合基线为 main `d293fd7dc8059902baf9bc9f591cf57892616f59`。交付分支为 `ui/motr7-artwork-20261114`。[PR #22 的分支头、合并状态及最终 main 提交](https://github.com/LSJOP/helldivers2-fx-launcher/pull/22)。

## V003 与 V002 的差异

- 应用场景、外壳、详情 Sheet、嵌套日志和编辑器共用滚动条策略。SwiftUI 隐藏滚动指示器，AppKit 补充关闭所在窗体 NSScrollView 的两向 scroller。继续保留容器、滚动位置、选择、复制及可访问性。未改系统偏好。
- 窄窗口以内容 760 点为断点，状态卡两列，最小高度由 72 减到 52 点；图标和垂直内边距缩小。主操作与实例卡保留可读字号，紧凑总览减少留白。
- 深色实例选中态改为接近中性的微暖深灰，浅色为暖白。沿用细边框、选中徽标、安装路径和真实操作目标。
- 折叠侧栏将同一透明金色徽章的最大绘制宽度从 52 点增至 64 点，保持居中。展开侧栏仍显示徽章、口号及条纹。
- 核对原有 FX 启动会进入待确认操作。保留授权门槛，将普通 FX 启动确认的文案缩短为启动所选 FX。游戏原流程、其他确认和危险操作条件维持原实现。
- 浅色士兵横幅使用较柔和的暖灰基底与渐变，保留原始图像和构图。六项导航、四张状态卡、三项 FX 操作、黄色游戏主按钮、金色徽章及城市原画均可在整合版显示。

## 冲突及保护

共解决 25 个冲突文件。文档冲突为 AGENTS.md、双语 README、双语 CHANGELOG、UI_DESIGN_GUIDELINES.md、截图 README 和 manifest。二进制冲突为中英文目录各 7 项（dashboard、environment、first-run-setup、fx-manager、logs、performance、settings）。保留历史 FX Manager 图和 main 的发布记录，从整合 App 重拍 README 当前引用的 12 项。

源码冲突为 Navigation.swift、SmokeRunner.swift 和 FirstRunSetupView.swift。内部待选 FX 路由沿用 .fx，外部仅六项导航。截图工具同时保留 main 的更新候选捕获和 V003 双语主题及滚动审计。首次运行保留 main 的凭据呈现和向导流程，只将重复扫描收敛到 Dashboard。

与 main 比较，Core、Services、UpdateHelper、Config、Info.plist 和 GitHub 工作流文件逐字一致。AppState 相对 main 的变化限于 DEBUG fixture。保留更新页面、版本 1.0.4（2026111601）、Ed25519/SHA-256 校验、独立更新助手和发布工作流。Xcode 工程的源文件引用反映移除 FX Manager 视图。维护了双方的本地化键和两种语言的已发布版本记录。

main 的测试仍期待已经移除的自动建 PR 流程。测试改为验证当前固定分支流程，继续检查 release 范围、签名验证、禁止创建 Release、禁止强推及无临时分支。工作流未改。

## 构建、验证和截图

- 原 UI 分支及整合候选分别完成 arm64 Debug 构建和完整 run_checks.sh。整合候选更新专项、发布验证 fixture、十语言、文档和截图门禁通过。
- 隔离的真实 App 检查了中英文深浅色宽窄窗口以及六页。深色宽窗和浅色窄窗各两种语言，通过 NSScrollView 测得顶部、中段、底部及自然纵向滚动范围，检查两个方向的 scroller 可见性。日志嵌套区也有独立滚动范围。在真实 App 激活 Logs 的 Copy 按钮，验证写入非空日志文本后恢复原剪贴板。
- [截图索引](images/reviews/dashboard-v003/README.md)收录选中／未选中实例、两种侧栏徽章、确认弹窗、性能、日志、设置和底部视口。[窗口滚动审计](images/reviews/dashboard-v003/scroll-audit.json) · [截图哈希和构建来源](images/reviews/dashboard-v003/manifest.json)。
- 实际 Mac 只有一套发现的 FX，多实例和目标切换使用隔离 DEBUG fixture。滚动审计由程序移动真实视图，独立的物理触控板、滚轮和键盘逐页输入未验收。日志 Copy 实际验证，手动逐字符选取未单独验收。
- 真实 FX 启停、Steam、Guest、SSH、游戏、EAC、联机、部署及完整正式更新链路均未执行。本轮结果限于视觉、交互和隔离回归范围。

## 修改文件索引

运行界面包括 App/HD2FXNativeApp、TacticalColors、TacticalComponents、TacticalTheme、ContentView、DashboardView、SidebarView、LogsView、SettingsView、FirstRunSetupView、Navigation 和 native-locales.json。验证涉及 SmokeRunner、capture_readme.py 和 update_resources_checks.py。文档包含本报告、双语 README/CHANGELOG、AGENTS、设计规范、状态和交接文档、双语图集及 V003 截图清单。
