# HD2FXNative 开发状态

更新：2026-11-14（Asia/Shanghai）。入口：[交接](NATIVE_APP_DEVELOPMENT_HANDOFF.md) · [规则](../AGENTS.md) · [文档索引](README.md)。

## 权威与基线

GitHub main 的源码、AGENTS.md 和本文件/交接文档是权威。聊天不代表进度。最后已知 main：`478d2bfdf0b75b92aaaf7516e5ddcd10d03309af`；本次文档任务不引入未通过门禁的候选代码。网络同步结果需以最终 Git 命令为准，不由本文假定。文档提交 SHA 用 `git log -1 -- docs/DEVELOPMENT_STATUS.md` 查询；接续前 fetch 并核对 origin/main。

## main 已实现（不等于全部实机验收）

| 功能 | 当前实现/边界 |
|---|---|
| 原生界面 | SwiftUI + 窄范围 AppKit，统一 AppState、TaskManager、Native Core；十语言资源、日志与主题 |
| FX | 有界发现、手动选择、签名/文件完整性、目标身份与配置绑定；不能以安装存在推断运行就绪 |
| 启动/首次配置 | 受保护的 FX/SSH/Steam/游戏启动、Guest 识别、部署计划/回执/恢复；候选审核失败必须阻止 |
| FEX/Proton | FEX 能力与候选构建/审核路线、固定 Proton-JE 校验和配置；禁止恢复未知组件 |
| 凭据 | SSH/sudo 独立会话内存、身份绑定及脱敏；main 尚无候选的 AES-GCM store |
| 网络/性能 | IPv6 显式预览/应用/恢复，CPU/RAM/Vulkan 配置及备份；真实兼容矩阵待验收 |
| 更新 | GitHub Release 检测、签名 manifest/下载与 Sparkle；生产分发和完整替换闭环未验收 |
| 构建 | arm64 本地 Release 与包结构检查脚本；ad-hoc 不等于公证/正式发布 |

模块定位见交接文档；历史细项在 FUNCTION_MIGRATION.md，不将其 2026-11-03 状态扩大为当前验收。

## 进行中：全分支整合候选

`integration/native-app-consolidation` 本地 `41af2ef`，尚未合并 main。来源包括 release/v1.0.0-integration、品牌提交 `6e93460`、recovery 的独有探测。已提交共享配置/启动、加密凭据、十语言品牌、更新归档绑定、配置更新源一致性修复。此前推送超时；远端持久化未确认。

源码交付 commit `cd27baa378f3fedb09153c1468bc6a03bbdefb26`（之后的文档提交以 Git log 为准，不将报告提交当构建源码）。本地候选版本 0.1.0；交付目录 `绝地潜兵脚本/APP 版本/Consolidation-20261114-cd27baa`。无公开 Release/标签创建。

备份在 `绝地潜兵脚本/Backups/consolidation-20261114-120725`：各 Worktree 暂存/未暂存 binary patch、未跟踪归档及 refs/log。部分克隆缺历史对象且网络失败，完整 bundle 未成功；不可删除原仓库。development、recovery、release-preparation 脏成果保留，独有差异尚未全部复核。所有活动分支/Worktree 与 legacy-script 保留；本阶段删除数量为 0。

## 已知问题、未完成与优先级

1. **P0：完成整合审查。** 核对候选和三个脏 Worktree 的独有差异、部署安全边界、更新安装失败回滚，不覆盖现有成果。
2. **P0：修复截图验收缺口。** 候选 UI 指纹与旧截图不匹配；完整 run_checks 门禁失败。真实十语言截图、菜单/Finder、文案与裁剪复核未完成，禁止只改指纹冒充通过。
3. **P0：可信更新闭环。** main 尚无候选的归档路径安装接入/更新源修复；候选生产公钥/feed、真实安装/失败恢复/重启仍待验证。不得关闭 SHA-256/Ed25519。
4. **P1：认证及部署实机矩阵。** 新 Guest、独立 SSH/sudo 密码、凭据更新/重启、身份漂移、FEX 自定义/官方版本、恢复及 Proton 缓存重试。
5. **P1：游戏/网络/性能验收。** 真正菜单、单人和多人分别记录；IPv6、FX 版本及 CPU/RAM/Vulkan 实机配置矩阵。历史菜单记录不证明当前包成功。
6. **P2：SteamOS 安全停止/重启。** 缺少可靠后端，保持不可用；不以强杀替代。
7. 所有必要门禁通过后从最新 origin/main 验证合并，再普通推送；保留清理建议，下一阶段才讨论删除。

本轮禁止修改真实 FX/FEX/FEXRootFS/Proton/Steam/macOS 网络，不启动游戏，不发布 Release。实机项目统一标记“待用户实机验收”。

## 测试证据与局限

下列是上一轮候选的本地证据，不是本次 main 重跑：arm64 Debug/Release、ad-hoc 包结构/资源/签名通过；十语言静态及品牌检查通过；SSH 37、privilege 30、network 66、Native Core 100、integration 27、identity 19、launch 23、session credential 29、encrypted credential 31、performance 15、selection 20、deployment 150、update service 36、update manager 23、FEX runtime 9、ZIP 7、docs 15 通过。

完整检查仍因截图门禁失败；功能检查是单独越过该文档门禁运行，不能表述为完整测试全绿。临时 runner 收尾还曾报告 FileNotFoundError，功能测试输出已保留。秘密扫描命中两处生成假凭据 fixture，不能把整个扫描写成无条件 PASS。Python 是隔离/静态测试；App 使用 Swift Native Core，不包含 Python 运行时。

证据：候选 `docs/development/NATIVE_CONSOLIDATION_20261114.md`（未合 main）、候选 worktree 的 `native-app/evidence/` 及交付目录。机器路径不是远端可用性的证明；下次需在实际 commit 重跑必要检查。

## 本次状态管理交付

建立两个当前入口并更新 AGENTS v1.2.19；整理旧开发指南的架构/构建说明，双语 README/CHANGELOG 加入口。纯文档改动，无 App 文案、界面资源或截图字节变化，十语言无需新增键；执行文档、链接、截图路径和 diff 检查，具体结果见本次 Git 提交/最终执行记录。

本次文档验证：双语文档检查 15/15、14 个截图引用的路径/来源/hash 检查、当前入口本地链接检查与 git diff --check 均通过。未更改 UI/本地化资源，未重编译 App。fetch GitHub HTTPS 连接超时；远端更新未确认，必须在网络恢复后重新 fetch/核对并普通推送，不得声称已上 GitHub。

## 本轮交接补充

本轮起点本地 main 为 `3e0539d`，远端仍仅最后已知 `478d2bf`；未完成全分支晋级。AGENTS v1.2.20 已将互相冲突的 Python Bridge/Keychain/旧阶段专用要求收敛为当前长期规则。模块边界、尚未整合分支、实际字节差异及可执行验收标准已补入交接。重新验证现有 cd27baa 候选 App 的 strict/deep 签名通过，未重构建、未修改真实环境。
