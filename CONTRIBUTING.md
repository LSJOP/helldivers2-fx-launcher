# 贡献指南 / Contributing

[README](README.md) · [架构 / Architecture](docs/ARCHITECTURE.md) · [发布计划 / Roadmap](docs/ROADMAP.md)

## 简体中文

欢迎改进教程、翻译、错误提示、兼容性记录、安装方案及启动器代码。普通玩家可直接通过 Issues 反馈，无需搭建开发环境。

### 从哪里开始

1. 阅读[依赖限制](docs/DEPENDENCIES.md)、[架构](docs/ARCHITECTURE.md)和[兼容性证据](docs/COMPATIBILITY.md)。
2. 下载源码或克隆仓库，在自己的分支进行修改。
3. 较大的安装、SSH、Keychain、网络或游戏启动改动，请先提交设计说明和预期副作用，再实现。
4. 提交 PR 时说明问题、修改后的行为、验证方式及仍未验证的部分。附上脱敏前提下的版本信息。

### 适合当前阶段的工作

- 中英文与其他现有语言的校对、无障碍和终端尺寸适配。
- 给未知状态明确提示，改善缺依赖与失败阶段的解释。
- 记录精确的组件来源、补丁、版本与可复现构建过程。
- 在独立环境中验证安装流程，并提交限定范围的兼容性结果。

### 本地检查

此玩家源码目录不附带内部测试夹具或维护日志，也没有要求玩家运行测试。维护者应在仓库外保留验证工具。

- 文档改动：检查相对链接、标题锚点、图片路径和双语内容是否一致。
- Python 改动：检查语法；增加有意义的隔离验证并说明如何复现。
- 入口说明：`zsh Start.command --help` 只显示帮助；`zsh Start.command --check-local` 只检查本地依赖，缺少运行组件时返回状态 3；状态 2 表示启动器基础文件缺失或损坏。
- 涉及真实 FX、SSH、Keychain、Steam 或网络写入：在独立环境中明确授权后验证，保留恢复路径，不在运行中的游戏上试验。

截图必须说明是离线界面演示还是实际运行；模拟结果不能证明游戏、EAC 或联机成功。报告应写“启动通过／未验证”“EAC 通过／未验证”“联机观察结果”各自的范围，不用一个“支持”概括全部结果。

### 隐私、来源和许可证

只提交必要源码与脱敏材料。不要提交个人设置、密码、私钥、令牌、Steam 账号、代理节点／订阅、原始日志、抓包、Guest 磁盘或二进制包。错误报告优先写最少量的已脱敏错误文字。

带入第三方代码或素材时，写清原作者、上游链接、精确版本／补丁与许可证文件。未经完成组件及依赖审查，不添加第三方二进制。项目尚未选择整体源码许可证；贡献意向、来源与后续授权需由维护者明确确认，本指南不建立额外的 CLA，也不把上游许可自动套用到本项目。

## English

Contributions can improve documentation, translations, terminal accessibility, status/error explanations, compatibility evidence and reproducible setup. Players can use Issues without setting up a development environment.

Start with [dependencies](docs/DEPENDENCIES.md#english), [architecture](docs/ARCHITECTURE.md#english) and [compatibility](docs/COMPATIBILITY.md#english), then work on your own branch. Discuss changes to installation, SSH, Keychain, networking or game startup before implementation. A PR should explain the problem, resulting behavior, validation and remaining uncertainty.

This player-facing tree excludes maintainer test fixtures and internal logs. Keep verification tools outside it. Check documentation links and image paths, check Python syntax when relevant, and provide meaningful isolated validation for behavior changes. `zsh Start.command --help` prints help; `--check-local` performs local checks and returns 3 when runtime components are incomplete, or 2 for missing/broken launcher basics. Real FX/SSH/Keychain/Steam or network writes need an explicitly authorized isolated environment and a recovery path.

Label screenshots and evidence accurately. Offline demonstrations do not prove game startup, EAC or multiplayer. Record those outcomes separately.

Do not submit credentials, account information, proxy subscriptions, personal configuration, raw logs, captures, VM disks or unreviewed third-party binaries. For third-party source/artwork, identify origin, version/patches and license files. The project-wide source license is unresolved; maintainers must confirm provenance and licensing terms before accepting or redistributing contributions. This guide adds no CLA and assigns no project license.
