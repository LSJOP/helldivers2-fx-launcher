# CODEX_NATIVE_APP_TAKEOVER_REPORT

核验日期：2026-11-04（Asia/Shanghai）。范围：接管现有纯 Swift Native 成果、修复 GUI SSH、补充构建身份、本机 Release 安全交付、更新 PR #3。未恢复 Python Bridge、重新设计 UI 或合并 main。

## 接管与 Git

- 工作区：`/Volumes/Thunderbolt2TB/HD2-Native-swift-core-20261103`。
- 已读取 AGENTS.md、历史任务队列及进度，检查全部四个 worktree、分支、未提交修改、远程分支及 PR。
- 接管基线：`0ba4e20f4897826391b77c81aa18ed74561dd9c0`；接管时工作区干净。`f219577`、`4814e39`、`0ba4e20` 均存在并已推送。
- 受保护的旧 Codex 工作区含未知 `docs/handoffs/` 和图片文件，保持原样；integration/main 与 launch-fix 工作区未修改。
- 初版实现提交：`7551dcb71c5f8dd8a68db590d2c55e9bb75c46fc`；第二版最终源码提交：`365dfadd9e297676d9f5f29315193c92d6b0fd8d`，已推送至 `feature/full-swift-native-migration`。
- PR #3：OPEN，开发分支已更新；报告后续提交只记录交付证据，不改变本次构建源码。报告所属提交的实际 SHA 以 PR HEAD / `git log -1` 为准。

## 原 Latest 二进制核验

| 对象 | SHA-256 |
| --- | --- |
| 原 Latest 可执行文件 | `3fbdaad4189f9e92231bc5d0374f38d39fb244bb28d64544148747fc258592e0` |
| 历史 f219577 Release 可执行文件 | `3fbdaad4189f9e92231bc5d0374f38d39fb244bb28d64544148747fc258592e0` |
| 原 Latest 与该 Release 的 Bundle 摘要（两者一致） | `3415e2be3d66ed6a839ee95f3719c13c710a3977e890e1e86f9548e8320e1966` |
| 初版新 Release 与当前 Latest 可执行文件（两者一致） | `ad03954e608b5d793221832dd1c0bb87f60f2b268b11ca58789235054c5f688a` |
| 初版新 Release 与当前 Latest 的 Bundle 摘要（两者一致） | `131981c8df8b8a1108799ee5e3412dd7bbc6ebf2ed6ecf63935bc62cc6629149` |

Bundle 摘要使用既有发布工具的路径、文件内容、权限、符号链接清单算法；未与可执行文件摘要混比。原 Latest 的 BUILD-INFO 指向 f219577；从 f219577 到基线 HEAD 只有文档修改。因此不能凭修改时间或文档 HEAD 判定旧发布失败。原包缺少内嵌提交元数据，回溯源码来源依赖外部 BUILD-INFO，不能把它当作独立源码构建证明。本次新增元数据解决以后识别问题。

旧构建缓存确实存在；本次 Release 使用全新 `.Build-Work/takeover-7551dcb-20261104/DerivedData` 与 Products，不复制旧主程序。接管时 PID 64884 确为旧 Latest；用户正常退出后已检查其消失。发布前无 Latest 运行进程；发布后确认新进程来自 Latest 路径。

第二版独立 Release 可执行文件：`da03aba2d101ee85a3c21eed84d2cf31e81a5effba999b918d1a75adaa05014d`；Bundle：`598f81140ecb7c8351189ac2151f9b4caf277bfb3c313d3b26c08da563b7217f`。第二版尚未替换 Latest，不能将其摘要报告为 Latest 摘要。

## FX 身份修复

`parseProcessTable` 裁剪 comm 对齐空格、supervisor/VM 子进程拓扑、可执行路径归一化、符号链接解析、WaitingForFXReady 与 VerifyingFXIdentity 均已在 f219577 提交及当前源码中确认；16 项身份回归检查通过。真实不同副本、异常拓扑、gvproxy 归属、SSH peer 和启动 CDP 归属检查仍保留。

独立 SSH 诊断不创建 CDP 转发，因此只对该诊断省略 CDP 转发检查；FX/gvproxy 归属与 SSH peer 身份仍验证。首次真实认证成功后，诊断发现当前 FX 使用其自带的 gvproxy，而不是启动器内置的 gvproxy-eim，导致路径过滤误报 gvproxy_not_child_of_fx。只读 ps 确认该 gvproxy 经 shell 属于所选 FX，所选 FX 的完整发布者签名和资源封印验证通过。后续修复只允许诊断在验证所选 FX 的发布者签名、资源封印、网络程序规范路径及签名前后内容哈希稳定性后，识别该自带后端；额外覆盖外来父进程、祖先循环及未签名伪造程序。游戏启动仍要求原固定内置后端与 CDP 检查。没有删除实例安全检查。

## SSH 根因与修复

已确认三处代码缺陷：

1. `Process.executableURL` 已为 `/usr/bin/ssh`，参数数组仍以 `/usr/bin/ssh` 开头，OpenSSH 会把它当成目标地址，使后续连接选项失效。已移除重复参数，测试保证只有一个可执行文件。
2. `Process + openpty` 未为 Finder/LaunchServices 场景提供 OpenSSH 读取 `/dev/tty` 所需的控制终端。原 Python `preferences.py` 使用 `os.forkpty()`；隔离复现显示普通 PTY 下 `/dev/tty` 打开失败。现在通过 macOS `/usr/bin/script -q /dev/null /usr/bin/ssh ...` 建立控制终端，无 Python 运行依赖。
3. 原 `testSSH` 未把 UI 密码/密钥口令传入 transport。现已传递，并同步传入用户实际选择的 FX；配置 revision 即使没有密码也需保持一致。

实际持久配置白名单核查：Host `127.0.0.1`、Port `2222`、User `steamos`、Auth `password`、CDP `18094`，不是仅审计默认值。初次端口探测为拒绝；后续只读探测确认 gvproxy 监听，且返回 `SSH-2.0-OpenSSH_9.7`。这只证明当时端口/协议入口存在，不证明密码认证或 Guest 身份成功。

保留现有 SessionCredentialManager 与 App 专用 Keychain、作用域及选择性保存流程；代理未通过工具读取钥匙串中的真实密码。只有本次实际密码挑战发送并成功，才发出可保存密码的认证事件；复用 master 或密钥口令不作为密码验证。密码不进入 argv、环境变量、文件或日志，PTY 关闭回显。主机密钥继续使用 `accept-new`，拒绝变更密钥；未关闭身份校验，也未修改 known_hosts。

底层失败区分：连接拒绝、超时、不可达、认证失败、主机密钥不匹配、本机端口占用、协议失败；缺少凭据沿用 `AUTH_REQUIRED` 以进入既有安全输入流程。保留截止时间、取消与单次认证，无密码失败重试循环。

原 Python 的 SSH 发现/参数、forkpty、Guest boot/marker 绑定、Steam 服务与游戏启动入口已对照审计；本次仅修复连接与只读诊断，不宣称整个 Swift 游戏事务已完成行为等价验收。

## 诊断与构建身份

运行环境增加“测试 Guest SSH 连接”，沿用安全凭据输入和明确操作授权。显示 FX 状态、实际地址/端口/用户、可达性、协商、认证、Guest 身份及阶段。使用独立临时 master、无转发；只执行 `id`、boot ID 与 SteamOS 标识读取，前后校验宿主实例。不启动 FX/Steam/游戏、不执行 sudo、不修改 Guest。

设置 → 关于包含 App `0.1.0`、Build `2026110402`、完整 Git 提交、实际构建时间、Swift Native Core `1.0.2`、实际运行路径及复制按钮。构建阶段写入 Bundle 内 `BuildMetadata.json`，运行时不依赖 Git；Release 拒绝脏源码。第二版 Release 时间为 `2026-11-03T19:58:14+00:00`（北京时间 2026-11-04 03:58:14）。初版独立 Release 和 Latest 的关于信息均经真实窗口目视核对；第二版构建元数据与进程路径已核对，电脑操作工具在构建后被移除，第二版关于页面尚未目视复验。

## 测试与构建

| 检查 | 结果 |
| --- | --- |
| Swift Native Core | 62 PASS |
| Native 集成 | 22 PASS |
| SSH 专项 | 17 PASS：参数、控制终端合成密码挑战、不回显、生产 transport 关闭端口与错误分类 |
| FX 身份 | 16 PASS |
| 启动/GUI 状态 | 18 PASS |
| 凭据模型 | 25 PASS（隔离 vault） |
| 性能模型 | 15 PASS |
| FX 选择 | 17 PASS |
| 十语言 | 10 × 495 键完整，0 gate 错误；负例 8 PASS |
| 截图/发行历史/更新资源负例 | 8 / 10 / 5 PASS |
| SwiftUI 集成 | 60 次真实页面/语言渲染 PASS，内嵌元数据检查 PASS；最终干净提交 365dfad 复验通过，无真实 Guest 操作 |
| 双语文档 | 15 PASS；README/CHANGELOG 同步 |
| Debug | 构建 PASS，冻结提交 365dfad、source_dirty=false |
| Release | 新 DerivedData 构建 PASS，arm64、图标、Bundle ID、十语言资源、gvproxy 哈希、无 Python/Bridge、内嵌元数据与签名均 PASS |
| 独立启动 | 历史 Release 副本主窗口与关于页面 PASS；Latest 主窗口与关于页面 PASS |

旧 `--ux-refinement` harness 在外部运行目录断言处得到 TARGET_GUARD_FAILED：它假设 Python 时代的外部资源契约。本次保留该失败证据，新增纯 Native 的 `--takeover` harness，未为迁就旧断言修改生产检查。英文/中文运行环境和设置截图已重拍并目视审查，其他六张/语言标为历史；十语言逐条自然度仍未做人工验收。

## 安全发布与回滚

最新 App：`/Volumes/Thunderbolt2TB/HD2-App-Builds/Latest/HD2FXNative.app`。

第二版独立 Release：`/Volumes/Thunderbolt2TB/HD2-App-Builds/Releases/0.1.0-365dfad-Release-takeover/HD2FXNative.app`。初版交付包也保留。

回滚：`/Volumes/Thunderbolt2TB/HD2-App-Builds/Releases/Rollback-20261104-035055-889022/HD2FXNative.app`，保留的可执行文件摘要与原 Latest 完全一致。

先验证独立包、签名、哈希与独立启动，再正常退出测试副本；确认 Latest 未运行后，使用原 `publish_verified_build.py` 校验、原子替换、保留回滚并复核。Latest/Release 摘要一致；发布后已从 Latest 启动并在关于页核对提交和真实路径。保留全部历史 Releases，未覆盖 /Applications。

第二版替换限制：用户再次正常退出 App 后，PID 68568 的 gvproxy-eim 仍在 Latest 包内为当前 FX 会话工作。未强行停止或覆盖；最新产物保留独立 Releases，等待用户决定是否正常退出 FX。

这是本机 ad hoc 签名的优化 Release，不是 Developer ID 签名/公证的正式分发包。未创建 GitHub Release、tag 或主分支合并。

## 真实验收与下一步

真实环境首轮（Build 2026110401）：用户在 App 安全输入框中输入凭据并主动勾选授权执行。端口可达、协议协商、密码认证均成功；FX 运行状态为 true。随后在 VerifyingGuestIdentity 因 gvproxy_not_child_of_fx 停止，未宣称 Guest 身份通过。该问题已在后续代码中修复，等待 Build 2026110402 复验。没有通过命令行传递聊天中的密码，也没有执行 sudo。

真实 SSH 密码认证已由首轮 App 诊断证实，但完整 Guest 身份仍未通过；Steam 启动、游戏启动、EAC 与多人联机未因端口、进程、哈希或隔离测试而标记通过。已在新版 App 打开独立诊断；真实密码应仅由用户在安全输入框内输入并明确执行，未使用聊天中的密码进行命令行认证。下一步先完成该只读诊断，确认具体失败阶段；保持 FX/Guest 身份检查。Steam/游戏和任何真实配置变更另按授权范围验收。

## Final publication update - 2026-11-04 04:18:49 Asia/Shanghai

This final update supersedes the earlier pending-publication statements above. The user normally exited FX; read-only process checks confirmed App, FX and gvproxy had all exited. Build 2026110402 / Core 1.0.2 / source 365dfadd9e297676d9f5f29315193c92d6b0fd8d was then published atomically to Latest using the existing publisher. No process was force-stopped.

- Latest executable SHA256: da03aba2d101ee85a3c21eed84d2cf31e81a5effba999b918d1a75adaa05014d
- Release executable SHA256: da03aba2d101ee85a3c21eed84d2cf31e81a5effba999b918d1a75adaa05014d
- Latest and Release bundle SHA256: 598f81140ecb7c8351189ac2151f9b4caf277bfb3c313d3b26c08da563b7217f
- Rollback of first takeover build: /Volumes/Thunderbolt2TB/HD2-App-Builds/Releases/Rollback-20261104-041849-522899/HD2FXNative.app
- Latest complete resource/signature/metadata gate: PASS. LaunchServices start and actual Latest process path: VERIFIED (PID 69864 at verification).
- Final clean-source Debug 60 page/language renders: PASS. Final About visual reinspection: NOT_TESTED after computer-use tooling became unavailable.
- First-build live password authentication: VERIFIED. Full Guest identity on final build, Steam start, game launch and multiplayer: UNVERIFIED. No further live authentication is inferred from the successful build or publication.
