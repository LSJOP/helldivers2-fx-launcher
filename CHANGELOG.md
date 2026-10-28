# 更新记录 / Changelog

版本信息唯一来源为 [`VERSION`](VERSION)。本文件记录历史，不参与运行时版本选择。UI 2.0 是界面名称，设置中的 `version: 1` 是数据格式，均不是启动器发布版本。

[`VERSION`](VERSION) is the authoritative release identity. This document is historical; UI 2.0 and configuration schema versions are separate concepts.

## 0.1.0-preview.1 — Unreleased

此版本号已获维护者确认，用于源码技术预览。尚未创建 GitHub Tag、Release 或完整安装包。 / Approved source-preview version number; no GitHub tag, Release or complete installer has been created.

### Added / 新增

- 受限模式：缺少游戏组件仍可打开 UI 2.0，保留语言、外观、帮助、本地检查和报告导出。
- macOS 原生 AppleLanguages 初始化，手动保存语言优先，失败静默回退 English。
- Python/Node.js 检查与已有 Homebrew 辅助安装；修改前确认，无 Homebrew 时提供选择。
- AI 辅助安装指南、中英文可复制提示词和安装流程。
- 统一版本文件、主界面／使用说明版本展示及诊断报告版本元数据。
- 中英文 README、离线 UI 预览、架构、贡献、兼容性、Issue 模板与阶段发布计划。
- Limited mode, native system-language matching, confirmed Python/Node setup, AI installation instructions, centralized version metadata and bilingual project documentation.

### Changed / 调整

- Start.command 与依赖安装脚本共享 Python 路径规则，并识别 Homebrew 的版本化 Python/Node 安装位置。
- Node 检查统一要求 22.0.0+ 以及原生全局 fetch / WebSocket；不通过联网探测判断。
- 游戏启动前重新检查本地运行依赖；未验证的 Guest 组件不计为缺失。
- Shared runtime selection and feature checks; runtime requirements are rechecked at the action boundary.

### Known limitations / 已知限制

- 完整安装、通用虚拟机位置识别、网络适配及跨机器验证仍未完成。
- 自动化测试使用模拟安装；没有宣称在干净机器完成了真实 Homebrew 安装或游戏／联机验证。
- 整体源码许可证、衍生素材权限及完整运行组件再分发仍待审查。
- Full runtime installation, fresh-machine validation and complete licensing review remain unfinished.
