# 发布计划 / Release roadmap

[README](../README.md) · [贡献 / Contributing](../CONTRIBUTING.md) · [兼容性 / Compatibility](COMPATIBILITY.md)

## 简体中文

这是按验收条件推进的计划，不是日期承诺。当前源码版本见 [VERSION](../VERSION)，为已确认的技术预览版本号；截至 2026-10-29 的只读检查，GitHub 尚无 Release。准备发布材料不等于已经创建标签、Release 或安装包。

| 阶段 | 面向谁 | 交付形态 | 发布前必须满足 |
| --- | --- | --- | --- |
| **Preview**（当前方向） | 开发者与已有匹配环境的玩家 | 源码、双语说明、界面预览、已知问题；若建立 Release，明确标为 prerelease/source-only | 链接与路径有效；事实／计划分明；Issue 入口可用；隐私扫描通过；来源和素材未决问题显式列出；未经确认的二进制不分发。 |
| **Beta**（未实现） | 愿意参与反馈的普通玩家 | 可复现的依赖准备流程和可安装预发布包；每个包记录版本、校验值和组件来源 | 识别 FX 位置；组件安装／备份／回退可用；网络配置与作者个人环境解耦；第三方及素材许可审查完成；独立干净用户环境安装到启动的真实验证；已有明确的硬件／系统矩阵和失败恢复说明。 |
| **Stable**（未实现） | 兼容范围内的普通玩家 | 经过验证、可维护的正式安装版本与简明升级／恢复指南 | Beta 阻断问题关闭；所有声称支持的组合有可复查证据；覆盖首次安装、再次启动、组件不匹配、更新与回退；声明的签名／公证流程已验证；用户文档和支持范围一致。 |

### 近期工作顺序

1. 完成 Preview 的文档、Issue、截图来源和许可问题清单，人工审阅后决定是否建立源码预发布。
2. 补齐精确组件的公开来源与可复现构建／安装流程，不用删除哈希检查替代兼容验证。
3. 设计首次安装引导、FX 位置识别和资源配置，先审计再实现。
4. 将网络准备变成用户可选配置；明确直连／系统网络与自定义代理各自的验证范围。
5. 在独立环境验证到真实游戏启动，再逐步收集联机证据，达到 Beta 门槛后发布。
6. 根据反馈完善恢复、升级和兼容矩阵，达标后评估 Stable。

项目源码许可证、既有衍生素材权限和第三方补丁来源仍待确认；不得把计划写成已完成。完整安装版不附 Steam 账号、游戏、用户磁盘映像或个人代理配置。未来即使支持某环境，也应分别描述启动、EAC 与联机的验证边界。

## English

This plan is gated by evidence, not promised dates. The current source preview version is recorded in [VERSION](../VERSION). A read-only check on 2026-10-29 found no GitHub Releases; preparing materials creates neither a release nor an installer.

- **Preview — current direction:** source, bilingual instructions, honest UI previews and issue templates for developers and users with matching environments. Validate links, paths, privacy and provenance notes. Any future source Release must be marked prerelease/source-only. No unreviewed binaries.
- **Beta — not implemented:** reproducible dependency setup and an installable prerelease for participating players. Require FX discovery, component install/backup/rollback, independent network configuration, completed component/artwork licensing review and real fresh-user installation-to-startup evidence. Publish an explicit compatibility matrix and recovery instructions.
- **Stable — not implemented:** a maintained installer for the evidenced support matrix, validated upgrade/recovery and any claimed signing/notarization workflow. Close Beta blockers and verify each advertised combination and first-run/restart/update/failure path.

Work proceeds from Preview documentation and rights review, through exact runtime provenance, reproducible setup and optional networking, to independent startup and multiplayer evidence. No project license is selected by this plan. Steam accounts, game files, personal VM images and proxy configuration are excluded at every stage. Startup, EAC and multiplayer remain separate claims.
