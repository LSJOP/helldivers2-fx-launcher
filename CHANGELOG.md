# 更新日志 / Changelog

[返回首页 / README](README.md) · [当前版本 / Current version](VERSION) · [版本规则 / Versioning](docs/VERSIONING.md)

版本信息唯一来源为 [`VERSION`](VERSION)。本文件按版本号倒序记录变更，最新版本在最上方；未发布条目不填写发布日期。UI 2.0 是界面名称，设置中的 `version: 1` 是数据格式，均不是启动器版本。

[`VERSION`](VERSION) is the sole release identity. Versions are listed newest first; unreleased entries have no release date. UI 2.0 names the interface, and `version: 1` in settings identifies the data schema. Neither is the launcher version.

## 0.1.0-preview.2 — 未发布 / Unreleased

维护者确认的下一版源码预览；此记录没有发布日期，不表示已创建 Git Tag、GitHub Release 或完整安装包。 / The next approved source preview. No release date, Git tag, GitHub Release or complete installer is implied.

### Added / 新增

- `[3]` 本机只读安装检测、九项部署指引及主动脱敏报告导出；Shell 缺 Python／Node 引导；无状态、不改写用户设置。完整游戏组件安装仍待确认。 / `[3]` local read-only setup checks, nine guide topics and explicit sanitized reports; Shell tool guidance; stateless and configuration-preserving. Complete game-component installation remains unavailable.

- `[2] 应用性能配置`：M1～M5 芯片分类、原生设备识别、现有配置状态与参数差异确认；未测试型号不分配虚构预设。 / `[2] Apply performance settings`: M1–M5 browsing, native hardware detection, real profile status and confirmed parameter diffs; no invented presets for untested models.
- `[6]` UI 2.0 离线帮助中心：九类主题、长页滚动、保留分类选择，简体中文与 English 正文，其他语言回退英文。内容读取实际版本、配置目录及更新能力。 / An offline UI 2.0 help center with nine topics, scrolling, retained selection, Chinese/English content and English fallback; version, profile catalogue and update capability come from existing modules.
- `[11]` 主动查询 GitHub 官方 Releases，无需 Token；SemVer 比较、保留 Preview／Stable 通道、版本／日期／日志摘要、在线及本地日志和 Releases 跳转。无 Release、异常元数据、超时及限流均有独立状态。 / Explicit anonymous official Releases checks with SemVer, retained Preview/Stable channels, version/date/notes, local and online changelogs and Releases navigation; missing releases, invalid metadata, timeouts and rate limits have explicit states.
- 用户数据存储清单、只读更新候选及本地修改检查、受保护路径拒绝与不落盘的默认字段合并辅助函数。 / User-data inventory, read-only candidate/local-edit checks, protected-path rejection and a non-persisting default-field merge helper.

### Fixed / 修复

- 更新中心进入时不联网，明确选择 [1] 才查询；[3] 日志、[4] 仅切通道、[5] Releases；展示附件元数据与手动下载限制。 / Update center entry is offline; [1] queries, [3] shows notes, [4] selects a channel and [5] opens Releases, with attachment metadata and manual-download limitations.
- 普通 HTTP 403 与有证据的限流分开；读取剩余额度、Reset 和 Retry-After，提前重试在内存等待期间不发请求。 / Generic 403 denial is distinguished from evidenced limits; remaining/reset/retry hints drive an in-memory wait with no early request.
- 补充独立更新器、文件归属、平台/版本、磁盘/备份、单独配置迁移及故障回滚的阶段 B 设计，执行器仍未实现，安装禁用。 / Stage B documents worker, ownership, platform/version, disk/backup, separate config migration and rollback gates; the executor is unimplemented and installation stays disabled.

- 更新页面支持仅本次查询的 Preview／Stable 切换，不保存配置；HTTP 错误显示状态码，响应中断和越界发布日期安全处理。 / Session-only Preview/Stable selection saves no settings; HTTP status codes are shown, and interrupted responses/overflowing dates fail safely.

- Guest IPv6、受管理 Steam 代理和完整 LaunchOptions 变更先展示差异并确认，保留私有备份及有限恢复；未知内容与并发修改不强制覆盖。 / Guest IPv6, managed Steam proxy and full LaunchOptions changes require review/consent, with private backups and bounded recovery; unknown content and concurrent edits are not forcibly replaced.
- EAC 使用本次请求前的文件身份、偏移及校验点；旧成功日志不作为本次结果。Steam 停止且空闲时最多受控启动一次。 / EAC uses pre-request file identity, offsets and checkpoints instead of historical success; idle stopped Steam can receive one controlled start.
- UI、CLI、兼容入口和后端共享必要依赖检查及目标互斥；身份无法核实禁止 Guest 写入。八阶段保留真实状态和耗时。 / UI, CLI, compatibility and backend entries share dependency and target-lock guards; unverified identity blocks Guest writes, and eight phases retain real state/timing.

### Validation / 验证

- 更新中心阶段 A 验收：567 项隔离测试通过，含 106 项更新测试及 8 项阶段 B 只读门禁测试；不代表安装或回滚已实现。 / Update center Stage A passed 567 isolated tests, including 106 update tests and 8 read-only Stage B contract tests; installation/rollback are not implemented.

- 本轮 Releases API 增量检查：隔离套件通过 497 项（在线更新 76 项）；2026-10-30 匿名实查返回 HTTP 403，不能据此判断仓库是否有新 Release。 / Releases API follow-up: 497 isolated tests passed (76 update tests); the anonymous live check on 2026-10-30 returned HTTP 403, so current release availability remains unknown.

- 本地隔离环境完整套件通过 483 项测试，包含 Mock HTTP、临时目录配置保留、失败／中断拒绝写入、版本读取及多语言布局。 / The isolated local suite passed 483 tests, including Mock HTTP, temporary-directory preservation, refusal of writes on failure/interruption, version reads and multilingual layout.
- 帮助页及菜单按 86×29、88×27、101×30、104×33 验证字符边界与滚动布局。 / Help/menu checks cover character bounds and scrolling at 86×29, 88×27, 101×30 and 104×33.
- 未进行干净 Mac 安装、真实 FX／SSH／Guest sudo／Steam／游戏／联机验收。 / No fresh-Mac install, real FX/SSH/Guest sudo/Steam/game or multiplayer acceptance was performed.

### Known limitations / 已知限制

- 安装更新保持禁用：尚无可信发布包、安装归属基线、独立替换程序及经过故障验证的自动回滚；实际文件替换清单为空。配置迁移也未启用。 / Update installation remains disabled: trusted packages, installed ownership, an independent replacement worker and fault-tested rollback are absent; the actual replacement list is empty, and migrations are not enabled.
- FX 实例关联仅 Mock 验证，真实进程拓扑仍需实机只读采样；无法确认时阻止写入，有限恢复不保证所有副作用可逆。 / FX association is Mock-tested only; real process topologies need read-only device validation. Unknown identity blocks writes; bounded recovery does not undo every side effect.
- 性能配置仍只有原有范围记录，未动态接入固定 FX CPU／RAM／GPU 启动参数。 / Only the historical scoped performance profile exists; it does not dynamically replace fixed FX CPU/RAM/GPU launch arguments.
- 原有普通设置验证器筛选已知字段，不能用于未来无损迁移；当前更新检查和帮助不写配置。 / Existing normal settings validation filters known fields and is unsuitable for future lossless migration; the current checker and help do not write settings.

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
