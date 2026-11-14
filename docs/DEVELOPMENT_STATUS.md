# HD2FXNative 开发状态

> 2026-11-14：品牌与首页五卡 LED 已整合，状态矩阵及中英文真实 Debug 截图完成检查；真实 EAC／联机成功仍未确认。

> 2026-11-14 日志与启动候选：为启动流程记录有界脱敏事件、任务 ID、耗时及本地时间显示；失败隐藏旧进度。FX 1.9.9 的只读状态与日志更新已验证，日志与首次配置页双语截图已更新；完整启动/EAC/游戏画面尚待验收；以当前任务分支和测试结果为准。

更新：2026-11-14（Asia/Shanghai）。入口：[交接](NATIVE_APP_DEVELOPMENT_HANDOFF.md) · [规则](../AGENTS.md) · [文档索引](README.md)。

## 当前交付：品牌与首页 LED 整合（2026-11-14）

- 已通过系统代理 fetch，远端 main 基线 `a99e1d35e42cd5423372ba909f53ff18a538cae1`，确认应用更名已合入。独立 `integration/brand-led-20261114` 工作树无冲突挑入 LED 候选 `58df1a8`，保留其他工作树与未提交成果；脏工作树补丁及未跟踪归档位于 `Backups/brand-led-20261114`。
- 首页保留 FX、虚拟机、Steam、EAC、联机。共用可测试状态映射：绿色仅表示已观察的进程或通过 Guest 身份验证的连接；进行中黄色、明确阶段失败红色、缺少／过期证据灰色。EAC 与联机无独立成功探测，保持未验证；不从游戏进程、菜单或单人记录推断。修复英文虚拟机标题截断，复用十语言现有 VM 文案。
- 最终整合源码 arm64 Debug 构建通过；真实隔离窗口中英文各十张采集审核，README 引用十四张来源／哈希门禁通过。截图来自 Debug 0.1.0 (2026111401)，不是正式 v1.0.0 的截图。
- 专项验证：55 项首页状态矩阵、23 项启动／GUI 状态回归、十语言静态资源、8 项本地化负例、10 种 bundle／App 品牌一致性、11 项截图门禁负例、15 项文档检查；详见本工作树 `native-app/evidence/`。矩阵检查调用与真实视图相同的映射，属于隔离输入检查，未执行真实 FX／Guest／游戏验收。
- 双语 README／CHANGELOG、截图来源和十语言资源同步；改动归属 Unreleased。正式 v1.0.0 DMG、标签与 GitHub Release 未改动。源码提交及远端确认以最终 Git 输出和 `git log` 为准，不在文档中循环填入自身 SHA。
- 推送前再次 fetch 得到 main `b789642fdb4eadb1d80c6578409e2a5044436fcb`（含同一 LED 候选及 8 项优先级检查）。合并保留远端历史；使用本轮 55 项共享证据映射矩阵替代较窄检查，保留已审核截图及双语页面展示。最终 App Swift／本地化资源与本轮已构建、采集的源码字节一致。其他活动工作树继续原地保留，本轮未写入。
- 待用户实机验收：EAC 加载、多人联机、真实运行状态变化和自动更新完整闭环；下一步仅在明确授权后测试对应项目。历史章节是阶段记录，以本节与最新 Git 为本轮进度。


> 最新远端核验：本轮 `git ls-remote origin refs/heads/main` 已确认 main 为 `954f88e500efc3f59630ccba2968c53cf0405cc4`，状态管理/交接规则已成功推送。此后本文件仅追加本次同步结果；最终文档提交 SHA 用 `git log -1 -- docs/DEVELOPMENT_STATUS.md docs/NATIVE_APP_DEVELOPMENT_HANDOFF.md` 查询并核对远端，避免自身 SHA 循环。
> `integration/native-app-consolidation` 的 `41af2ef890e10e7d636ef31205a4fc3c03845536` 也已普通推送 GitHub，作为候选备份，**尚未合并 main**。下文网络失败说明是先前尝试的历史记录，已被此次成功同步取代；其余截图/差异/更新闭环阻塞仍成立。


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

## 继续整合检查点（2026-11-14）

候选已合入 main `50f3ecae9fd545bc6aacbda6c4665f089db64feb` 的规则/文档，保留双方 README/CHANGELOG。新增安装边界缓存重验（SHA-256、Ed25519、ZIP 路径和拒绝符号链接），增加下载后篡改/链接测试。更新服务 39 项、更新管理 23 项及 ZIP 7 项隔离检查通过。未完成 Sparkle 实际替换/失败回滚/重启隔离闭环；不得将重验测试称为安装闭环完成。

已从当前候选新建 Debug 构建并启动隔离捕获副本，禁用凭据加载和 Guest 操作。捕获未产生请求，CUA getApp 接口 timeoutReached；截图未通过，不改写 provenance 或视觉 PASS。main 晋级继续阻塞。实际最新代码/构建提交通过 Git 和 SOURCE-COMMIT.txt 核对，cd27baa 仅保留历史。App 版本维持 0.1.0，构建号更新为 2026111401。

### 新候选交付与截图后续

最新 Release 源码 `4e104b7936fc20e2e7a5ef763f9ea4af6163525c`，0.1.0 (2026111401)，arm64，source_dirty=false。输出：`绝地潜兵脚本/APP 版本/Consolidation-20261114-4e104b79/HD2FXNative.app`，ad-hoc/资源/来源检查通过；不是 cd27baa 旧包，也不是已合入 main 的包。此前“未产生请求”的说明只适用于首次英文尝试：中文随后捕获成功，原图在候选 worktree `native-app/evidence/capture-resume-zh`，dashboard/settings 已视觉查看，其他图片及英文/其余语言尚未完成审阅。未改写截图 manifest。完整截图门禁依旧失败。

本轮更新测试已通过，不等于 Sparkle 安装/回滚/重启闭环通过。main 仍保持 50f3eca，整合尚未结束；候选已合入 main 的规则，AGENTS v1.2.20 本轮无需规则变更。下一步先解决英文捕获/全语言审阅，再完成真正隔离安装闭环和独有分支差异审查，不能继续以补文档代替这三项工作。

## 跨机器接续检查点（2026-11-14）

已 fetch：main 为 `50f3ecae9fd545bc6aacbda6c4665f089db64feb`，整合基线 `78a9eca99f4475598b77bce0a2de35e93c693197`。新工作树 `Worktrees/HD2-Native-consolidation-resume`；24 个注册工作树中仅 full-audit 有修改，原地保留并将 HEAD、暂存/未暂存二进制补丁及未跟踪文件归档到项目目录 `HD2-native-resume-backup.cTKVBdE4`（私有权限）。旧交付路径位于另一台电脑。

本机源码 `8f4c39601ccc680606bb8b77916f2e952a9b15ce`：隔离捕获工具支持十语言，修复首页整秒时间戳未转换为上海时间。英文及简体中文各七张 README 图来自同一源码的本机 Debug 0.1.0 (2026111401)，完成视图审查和哈希门禁。其余语言的截图、菜单/Finder、窄窗口及动态错误文案仍需审阅。十语言静态资源均为 620/620。新 arm64 ad hoc Release 候选在 `HD2-App-Builds/Candidates/Consolidation-20261114-8f4c396/Products/HD2FXNative.app`，资源、签名、架构与来源核对通过；没有替换已安装 App。

已对照四个未成为祖先的远端 Native 分支：品牌分支的 InfoPlist 本地化文件与候选字节一致；recovery 核心 FEX/Proton 与候选一致，候选另有 SSH 进程隔离、流程重置和性能范围保护，保留较简洁的 FX 卡片，未合入 recovery 固定版本/内存展示。release 分支与候选核心差异为候选额外的 FEX helper 注册检查、启动前能力重验及更长的首次启动等待。release-preparation 的早期更新预检保留在候选，候选新增缓存边界重验、加密凭据和共享首次配置。旧分支与另一台机器的脏成果继续保留；本机 full-audit 未提交差异及异机未跟踪文件仍需逐项处置。

更新服务 39 项、管理器 23 项、资源 5 项、发布历史 10 项、ZIP 7 项通过隔离检查。仍需用独立签名测试 feed 和临时 App 路径验证 Sparkle 自身下载、解压、替换、故障回滚与重启；当前没有完整安装验收。main 不晋级，真实 FX/FEX、Steam、EAC 和联机均未执行。

补充验收：未跳过任何门禁的 `native-app/script/run_checks.sh` 退出 0，共 547 项 Swift 功能检查通过，另含脚本内静态和 Python 检查。十语言各捕获 10 张真实窗口，已浏览页面布局及语言；[捕获清单及哈希](development/NATIVE_UI_CAPTURE_20261114.json)，原图保存在本机候选工作树 `native-app/evidence/resume-current`。长侧栏标题在部分语言会换行；FX 管理和设置图有滚动下方的内容。菜单/Finder、狭窄窗口、错误状态和翻译自然度仍未完成全部验收。

本机 full-audit 的未跟踪加密存储源码与候选字节一致，其凭据测试已被候选的扩展版本覆盖。独有的任务队列续接测试依赖仅该工作树有的 API；候选使用统一环境流程，未搬入旧任务续接。保留该工作树中的 Guest 停机/重启、Proton Guest 缓存续传及 FX 独立性能域实现：分别待隔离生命周期、下载并发/缓存和配置恢复审核，不直接启用。其余旧机未推送文件仍不可在本机核对。Release 候选的生产更新配置为关闭；不通过启用生产源来做故障测试。

## FX 1.9.9 测试机实机验收（2026-11-14）

- 测试 FX 实际路径为 `/Applications/FX Steam Launcher测试用.app`，Bundle ID `es.fxgam.steamtc`，live 进程打开 `steamos_test.img` 并经候选自带 gvproxy 监听 `127.0.0.1:2223`。正式 1.9.12 的 Bundle ID 为 `es.fxgam.steamac`，配置指向独立 inode 的 `steamos.img`，检测时未被打开。
- 已创建测试盘 APFS 写时复制备份和测试偏好导出，位置 `/Volumes/Thunderbolt2TB/FX199-acceptance.Hf7i5ujA`。测试 VM 在比较期间启动，cmp 报原盘与备份不同，备份未达到恢复验证标准。历史清理回执仅用于识别范围，本次没有执行删除或还原，也没有更改 IPv6。
- 通过候选 GUI 启动 FX，已看到启动成功、SteamOS SSH 连接成功、首次配置检测。沿用已有加密凭据，未覆盖或清空凭据，因此尚未验收真正新用户的首次保存或重启后恢复。FEX 通过文件与架构检查，来源未验证，App 出示指纹并请求一次显式同意，停在兼容性执行探针之前。sudo、环境部署、Steam、游戏进程、主菜单、单人任务及多人均未验证。现场截图和进程证据保留在备份目录。
- 在源码 `6a518f09ce7ffb29b744f8d89d14634a0f5a6fdf` 重跑完整检查及更新专项成功，构建独立 arm64 ad hoc App `HD2-App-Builds/Candidates/FX199-20261114-6a518f0/Products/HD2FXNative.app`，版本 0.1.0 (2026111401)，资源、架构和签名校验通过。现场 GUI 使用上一份 `8f4c396` 构建，二者 native-app 源码无差异。此次无 App 源码或十语言资源变更。

### FEX 来源核验修订

实机重新核对了 FX 1.9.9 的测试盘和 2223 监听，正式盘未打开。代码改用预检返回的同一份文件树指纹匹配安装审核回执，并在运行探针之前重新计算和比对，避免两次独立读取得到不同文件树时错误继承信任。回归用例分别验证匹配与不匹配。现有 FEX 尚无已验证的对应回执，仍需可信上游完整安装清单或经审核的替换件，不能将当前指纹直接加入信任。未重置测试盘或配置，后续 sudo、部署和游戏阶段均未执行。

独立 arm64 ad hoc 候选位于 `HD2-App-Builds/Candidates/FX199-provenance-20261114/Products/HD2FXNative.app`，源码 `d40975e2dbde9ec2803cf43240df1be70cc2da6a`。可执行文件 SHA-256 为 `db3e927fed60a38a81f1b19ca61dc8b18c4d8be797d84e4cbcb995c11ded61cf`。此构建用于验证来源逻辑修订，正式验收交付与构建号升级待完成。


### FX 1.9.9 RootFS 启动排查

13:39 启动已生成指向 /usr/share/guestos/fex-mesa 的配置。测试 Guest 证实该目录的 provider 文件与 x86-64 loader 存在。失败子进程在 pressure-vessel 后报告 RootFS 为空。新增 Guest 侧先决条件检查及缺失 loader 回归测试，未改变真实 Guest 配置。下一步使用同一次启动中的容器内环境和实际 FEX 配置定位丢失点，完整游戏验收仍阻塞。此检查仅覆盖 SteamOS 默认 provider，不建立容器内就绪证据。

### FX 1.9.9 容器 RootFS 对照实验

在测试 Guest 用 Steam 的 FEX wrapper 与 Steam Linux Runtime 4 执行动态 x86-64 探针。原始 emulator.json 的 container_environment.FEX_ROOTFS 为空，进入容器后覆盖外层传入的值。只在临时 FEX 副本把该值设置为 /run/gfx/main，容器收到正确值并且动态探针退出 0。核对测试盘和 Guest machine ID 后同样修改测试 Guest 的 emulator.json，原件备份于 /home/steamos/.hd2-rootfs-backup-sfvym6ou，实装探针退出 0。游戏菜单仍需单独验证。文件变动会改变 FEX 文件树审核指纹。App 尚未自动应用此修复，后续需要版本与目标绑定的部署/回滚及容器内探针。


## FX 1.9.9 RF 恢复及 GUI 启动（2026-11-14）

本轮实际证据见 [修复报告](environment/FX199_RF_REPAIR_20261114.md)。正式盘未写入；测试盘十文件有完整备份及回执。GUI 启动/EAC 引导/游戏进程窗口通过，主菜单或飞船由用户确认，单人/多人按用户选择未测。下一步完成新 UI 截图、回归和内部候选；自动更新真实安装闭环与玩法门禁未过，不发布公开 Beta。当前任务分支以 Git 实际 HEAD 为准。

最终内部 RC：1.0.0 (2026111403)，干净构建源码 `4119d65e64468afaa763cf8ffc134a34786bb83f`；DMG `/Volumes/Thunderbolt2TB/绝地潜兵脚本/HD2-App-Builds/Candidates/FX199-RC-20261114-2026111403/HD2FXNative-v1.0.0-macOS-arm64.dmg`，SHA-256 `59730d98f3a4c358ca335da481d170f57c452d075728441147aa38723c50a478`。arm64 Release、ad-hoc、资源/秘密扫描、DMG 校验/只读挂载/安装副本及卸载后实际进程启动均通过。最终完整核心检查 549 项及更新专项通过；末次仅补面板重试入口并重新 Debug/Release 编译，未声称重跑全部核心测试。终态按钮动态交互、真实更新安装/恢复和单人/多人仍待验收；不发布、不合 main。源码分支 `fix/fx199-verified-rf-20261114`，远端以实际 ref 查询为准。


## 用户授权 main 合并（2026-11-14）

用户已明确授权将 FX 修复与 UI／凭据／更新安全候选合并 main 并推送。以最新 origin/main 0eb1f3e 整合候选 7a16400；保留 main 已发布 v1.0.0 的下载入口和发布说明，旧记录中“不合 main／尚未发布”仅描述当时阶段。GitHub API 已确认现有 v1.0.0 为公开稳定版，资产与候选同一 DMG。本次不发布、替换或删除 Release、tag 或安装包。保留全部真实玩法、sudo、凭据及更新完整闭环的未验收限制，不因源码合并而升级状态。

集成冲突仅涉及双语 README/CHANGELOG；Native 代码及资源与已验证候选逐字节一致。full-audit 工作树的未提交成果未改动，其补丁和未跟踪文件另存 Backups/main-merge-20261114。main 工作树原本干净；合并通过必要检查后普通推送，实际提交/远端状态以 Git 为准。

本次 main 整合验证：Debug 构建通过；完整 run_checks.sh 及更新专项均退出 0，549 项 Swift 核心回归通过，更新服务 39／管理器 23 及归档相关检查通过；十语言、14 图来源、双语文档、diff 与暂存秘密扫描通过。整合期间保留远端后续 fa82837 的 README 排序与凭据说明；源码合并不等于新增实机验收，也不重建已发布 DMG。

## 自动更新隔离候选 · 2026-11-14

基于远端 main `cd42dca30c85d5762c5f7cad9270850dc78d4e3d`，独立分支 `feature/native-auto-update-20261114`。候选将「下载并安装」接至既有校验下载再交给 Sparkle，并使原生检测/下载时的取消入口可见；无新增翻译键。现有生产公钥、服务和分发就绪标志仍为空/关闭。v1.0.0 标签配置亦如此，因此该旧版不能安全地自动引导到新信任根，需可信手动安装一个已配置公钥的引导版本。

候选未完成：Sparkle 仍会另行下载并可能弹确认；真实隔离升级、故障注入、重启确认、安装后自动回滚、正式签名密钥和发布链路未完成。不能当作可发布的自动更新功能。不得覆盖 v1.0.0、发布 v1.0.1 或修改游戏环境。接续先设计可信引导及独立辅助程序恢复协议，再进行隔离端到端验收。具体验证和源码 SHA 以本分支 Git 记录及最终报告为准。

截图门禁因更新界面源码变化而失败；中英文真实截图尚未重拍及复核，不应视为已通过。

## 应用名称统一 · 2026-11-14

简体、繁体名称与其他语言英文名称已统一；保留内部 App 文件名、Bundle ID 和数据位置。v1.0.0 更新服务未配置，不能据更名推断自动升级可用；实际升级验收仍待完成。截图为历史构建，更新后的真实截图待采集。

首页 LED 整合：品牌 main 已包含，状态颜色组合隔离验证，中英文首页 Debug 截图已更新；其他页面截图待复核。EAC/联机未做实机验证。

未完成：LED 八种布尔组合仅验证纯逻辑优先级，未完成真实状态注入的界面颜色矩阵及运行时动态验证；FX/Steam 进程检测仅显示灰色“已检测到进程”，不能当作完整就绪。完成矩阵及审核后才可晋级 main。

## v1.0.1 更新接续 · 2026-11-14

已整合包含品牌及 LED 的 main b789642；保留既有更新签名和 ZIP 检查。候选版本 1.0.1/build 2026111404，公钥固定在 Updates.xcconfig。独立 update_signing.swift 以仓库外 0600 文件管理私钥，不访问 Keychain，不打包到 App。原 prepare_native_release.sh 为历史 Keychain/Developer ID 路线，本轮未执行，不适用于本次无 Keychain 交付。

未完成：重复下载/确认消除、独立安装和健康确认/回滚协议、真实 1.0.1→1.0.2 升级及故障矩阵。仅配置公钥不代表服务就绪，保留服务关闭。未发布 Release、未晋级 main。截图与真实安装仍需完成，草稿 PR 必须保持未合并。

本轮验证：1.0.1/2026111404 arm64 Debug 构建通过；更新服务39、管理器24、资源5、历史10、ZIP7检查通过；文件签名工具验证通过；十语言596键、双语文档15项及 App产物秘密扫描通过。真实中英文截图驱动运行成功，但更新区域滚动位置错误，截图待修复重采集。真实安装/回滚未执行，不能晋级 main。

## 独立安装助手候选 · 2026-11-14

Swift 服务保留签名清单原始字节和签名，将已经下载的 ZIP 交给单一 Helper。Helper 从当前 App 读取固定公钥，用复制到私有事务目录的归档复验 SHA-256、Ed25519 和 ZIP 结构，然后提取并校验 App 签名、版本、Bundle ID 和公钥连续性。旧 App 在 Helper 提示准备就绪后正常退出。Helper 使用同卷原子交换保留旧包，新 App 主窗口可见后写出本次启动令牌。未收到令牌或进程提前退出时恢复旧包并确认其启动。事务日志保存在安装目录旁。Sparkle 运行时的安装入口移除，历史打包和框架依赖保留。

隔离测试使用临时密钥和实际 ad-hoc 签名的 AppKit 测试包，不读取正式私钥或用户数据。Helper 若被强制终止，现场、日志及交换后的旧包会保留在 .HD2FXNative-update，后续安装会拒绝覆盖。自动接管中断事务、真实启动器单击跨版本升级和用户配置保留验收仍待完成。生产服务继续关闭。

PR #4 已发布隔离签名更新测试包 v1.0.1-update-test.1 和 v1.0.2-update-test.1，稳定版服务保持关闭。真实设置页升级须以下载日志、启动确认及设置对比验收。

2026-11-14：隔离 GitHub 更新已实测保留真实 FX 测试路径、语言和主题。实际低空间卷、不可写安装目录及中断恢复通过。v1.0.1 构建 2026111406 使用 GitHub Releases 稳定渠道。
