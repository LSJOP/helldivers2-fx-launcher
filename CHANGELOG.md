# 更新日志 / Changelog

[返回首页 / README](README.md) · [当前版本 / Current version](VERSION) · [版本规则 / Versioning](docs/VERSIONING.md)

版本信息唯一来源为 [`VERSION`](VERSION)。本文件按版本号倒序记录变更，最新版本在最上方；未发布条目不填写发布日期。UI 2.0 是界面名称，设置中的 `version: 1` 是数据格式，均不是启动器版本。

[`VERSION`](VERSION) is the sole release identity. Versions are listed newest first; unreleased entries have no release date. UI 2.0 names the interface, and `version: 1` in settings identifies the data schema. Neither is the launcher version.

## 0.1.0-preview.1 — 未发布 / Unreleased

此版本号已获维护者确认，用于源码技术预览。尚未创建 GitHub Tag、Release 或完整安装包。

This approved version identifies the source technical preview. No GitHub tag, Release or complete installer has been created.

### Added / 新增

- 受限模式允许缺少游戏组件时打开 UI 2.0，保留语言、外观、帮助、本地检查与报告导出。 / Limited mode keeps UI 2.0, language, appearance, help, local checks and report export available without game components.
- macOS 原生 AppleLanguages 初始化；手动保存的语言优先，失败静默回退 English。 / Native macOS language initialization respects saved manual choices and silently falls back to English on failure.
- Python／Node.js 检查与已有 Homebrew 辅助安装；修改前确认，没有 Homebrew 时提供官方安装方式。 / Python/Node checks and confirmed installation through existing Homebrew, with official alternatives when Homebrew is absent.
- AI 安装指南与可复制的中英文完整提示词。 / AI installation guidance with complete copyable Chinese and English prompts.
- 统一版本文件；主界面、使用说明及诊断报告展示启动器版本。 / Centralized version metadata for the main screen, instructions and diagnostic reports.
- 中英文 README、离线 UI 预览、架构、贡献、兼容性、Issue 模板与阶段发布计划。 / Bilingual documentation, offline UI previews, architecture and contribution guides, compatibility records, issue templates and a staged roadmap.

### Changed / 调整

- 启动入口与安装脚本共享 Python 路径规则，识别 Homebrew 版本化 Python 与 Node 的安装位置。 / The shortcut and installer share runtime-path rules, including versioned Homebrew Python and Node locations.
- Node 检查要求 22.0.0+ 及原生全局 fetch／WebSocket，不发起联网探测。 / Node checks require version 22.0.0+ and native global fetch/WebSocket without making network requests.
- 游戏启动前重新检查本地运行依赖，未验证的 Guest 组件不计为缺失。 / Local runtime requirements are rechecked before launch; unverified Guest components are not counted as missing.
- 环境状态采用独立状态栏与警告色，保留黄色 Logo 和终端颜色回退。 / A separate environment status bar and warning color preserve the yellow logo and terminal color fallbacks.
- README 提供双语 AI 入口、并排 UI 截图、小屏大图、原生 Markdown Alerts，以及语言导航旁的更新日志链接。 / The README provides bilingual AI links, paired UI previews, full-width expansion, native Markdown Alerts and a Changelog link beside language navigation.

### Fixed / 修复

- 中英文安装命令从实际项目根目录运行，不再假设 Downloads 或固定解压名称；兼容空格、中文名称与移动后的目录。 / Installation commands use the actual project root instead of a fixed Downloads folder or archive name, including renamed/moved folders, spaces and Chinese paths.
- 诊断导出会过滤已知历史字段中的凭据样式文本；仅完整有效的时间戳与结构性 UUID 引用保留相应豁免，维持记录关联与统计。 / Diagnostic exports filter credential-shaped text in known historical fields while preserving valid timestamps and structural UUID references for correct record associations and statistics.
- 地址、TCP 测量或历史统计缺少结果时显示“未验证／未知”，不直接显示内部 `None`。 / Missing address observations, TCP measurements and history metrics display unverified/unknown instead of raw `None` values.

### Known limitations / 已知限制

- 完整安装、通用虚拟机位置识别、网络适配与跨机器验证仍未完成。 / Full installation, general VM discovery, networking adaptation and cross-machine validation remain unfinished.
- 安装分支使用模拟工具测试，没有宣称在干净 Mac 上完成真实安装、游戏启动或联机验收。 / Installer branches are tested with mock tools; this does not establish successful installation, gameplay or multiplayer on a fresh Mac.
- 整体源码许可证、衍生素材权限与运行组件再分发仍待审查。 / Project-wide licensing, derived-artwork permissions and runtime redistribution remain under review.
