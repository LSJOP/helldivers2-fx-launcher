# 在线更新 / Online updates

[README](../README.md) · [版本规则 / Versioning](VERSIONING.md) · [更新日志 / Changelog](../CHANGELOG.md)

## 当前可用功能

主菜单“设置与工具”新增 `[11] 检查更新`，沿用 UI 2.0、Logo、颜色和键盘操作，支持现有十种语言。检查仅由用户主动进入时执行，不在启动／游戏流程中自动联网。

```text
[11] 检查更新
  当前版本 / 当前通道最新版本 / 发布日期 / 通道 / 状态 / 日志摘要
  [1] 查看更新日志
  [2] 下载并安装更新（未开放）
  [3] 打开 GitHub Releases
  [0] 返回
```

**本轮开放第一阶段。安装入口始终禁用。** 2026-10-29 检查仓库 Releases 列表为 0 项，尚无可信更新包、安装归属基线及经过验证的独立更新器。未来即使出现附件、下载地址或哈希字段，当前代码也不会自动开启安装。

版本唯一来源仍是根目录 [VERSION](../VERSION)。使用官方公开 [List releases API](https://docs.github.com/en/rest/releases/releases#list-releases)，不读取 GitHub Token、不要求 gh 或 Git，不把 main、普通 Git tag 或提交当作 Release。

比较遵循 [SemVer](https://semver.org/)，数字预发布编号按数字比较，构建元数据不影响先后顺序。默认通道规则明确如下：

| 本地版本 | 默认查询 |
| --- | --- |
| 正式版本（无 `-` 标识） | 正式 Release，拒绝 prerelease 标记不一致的数据。 |
| `-preview.N` | 仅 preview，不自动跨到 beta、rc 或正式版。 |
| `-beta.N`／`-rc.N` 等 | 保持其首个预发布标识，不自动换通道。 |

未提供跨通道切换按钮。无 Release 显示“暂无可用发布版本”，只有其他通道时明确说明。草稿、非 SemVer 标签、无发布日期及 tag／prerelease 标记不一致的条目不会被当作候选；有异常数据时不伪称仓库没有发布。版本比本地旧时不建议降级。

请求使用默认 TLS 验证，只接受固定官方仓库 API，不携带认证头，拒绝重定向；分页地址自行构造，不追随远端任意 Link URL。单次 socket 超时 8 秒、最多 5 页、每页响应最多 1 MiB。遇到超时、断网、限流、超出边界或无效元数据时返回错误状态，不退出启动器。没有依赖版本安装或网络设置修改。

Release body 是在线摘要；完整说明与本地 CHANGELOG.md 可在 `[1]` 查看。远端文本仅作带分隔前缀的终端文本展示，去除控制／终端转义，不执行 Markdown、Shell、HTML 或其中的链接。`[3]` 只打开固定的[官方 Releases 页面](https://github.com/LSJOP/helldivers2-fx-launcher/releases)。

配置存储位置、只读保护检查及尚未启用的迁移／恢复约束见[用户数据保护](USER_DATA.md)。发布资源字段会作为官方 API 元数据解析，但不会下载，也不会凭资源存在而开启安装。

2026-10-30 使用当前源码匿名复查时收到 API 限流状态；界面可正常显示失败原因并返回。此前 0 项是 2026-10-29 的观测，不视为永久仓库状态。

## 实际更新范围

**第一阶段实际文件替换清单为空：不会下载资源、解压、替换任何文件或改变 VERSION。** 对 ZIP、Git clone、移动后的中文／空格目录同样适用；检查功能不依赖安装路径和 .git。用户设置、SSH 凭据、日志、诊断历史、FX／Steam／游戏进程均不参与检查。

[受管理文件草案](update-managed-files.draft.json) 逐项列出当前可考虑由未来更新器管理的源码、UI、语言、工具和随附文档。它是设计稿，不包含可用哈希、不被当前代码当作文件归属证据，也不是可安装 manifest。未来每次发布仍需审查此清单；新增或删除文件不能被目录通配自动接受。

永远排除 FX.app、FEX、Proton/Wine、gvproxy-eim 二进制、Steam、游戏文件、.git、用户配置、凭据、known_hosts、Keychain、backups、reports、diagnostics、settings.json 及本地历史。现有 gvproxy wrapper 是源码脚本，和 gvproxy 二进制分开处理。

## 第二阶段设计：受控事务，尚未实现

1. **可信发布元数据。** 固定官方 repository／Release ID／tag／asset ID 和版本，验证 HTTPS。预期包 SHA-256 必须来自官方 API 的独立可信 `asset.digest` 或经固定维护者身份／密钥验证的签名与证明，不接受只与包同源的未认证 SHA256SUMS。API 哈希缺失、不可信、资源归属不清或被重定向到未经允许的位置时停止，不降级为“校验通过”。GitHub 的资产字段见[官方文档](https://docs.github.com/en/rest/releases/assets#get-a-release-asset)。
2. **现有文件归属。** ZIP 安装需要可信的当前版本发布 manifest；不能现场散列用户当前文件后把它们认定为官方原件。Git clone 也必须匹配官方发布基线，工作区有未提交改动或来源不明则停止。当前 main ZIP 没有这个可信基线，应手动迁移，不能强制认领。没有 git pull/reset/clean 或全目录镜像覆盖。
3. **确认与下载。** 用户确认精确目标版本、清单和变更后，下载到私有临时目录。包 VERSION 必须与可信 Release 版本一致；只读取文件，不执行包中的任何安装程序。
4. **压缩包校验。** 拒绝绝对路径、`..`、NUL、符号链接／硬链接逃逸、非普通文件、未列入清单的条目、重复名称、大小写或 Unicode 规范化冲突，以及超出文件数／大小／解压上限的包。校验每项路径、哈希和权限，不跟随目标目录的符号链接。
5. **退出交接。** 从当前已安装的可信代码启动独立更新程序，而非运行下载包中的程序。更新器与所有启动入口共享基于同一真实项目根目录的生命周期锁，验证父进程身份并等待启动器完全退出。无法确认其他入口是否仍在执行时停止，不靠 PID 存在或单个设置目录锁猜测。不会结束 FX、Steam 或游戏，也不强制终止别的启动器。
6. **备份和替换。** 备份仅涉及已验证归属的受管理文件；私有目录 0700、备份数据 0600。记录原／新哈希、文件身份和受控权限，重新检查本地修改，使用同文件系统的暂存与逐项原子替换，持久化事务日志。不能宣称多个文件的替换整体天然原子。
7. **恢复。** 失败或下次发现中断日志时，按日志恢复本次已改变的受管理文件，先验证身份和现值，不覆盖期间发生的新用户改动。断电、磁盘故障、恢复写入失败或身份冲突时保留备份并报告手动处理，不继续破坏。成功后只提示用户重新打开 Start.command，不自动执行新包。

以上是设计约束，当前没有下载器、解压器、文件替换器、后台更新程序或自动回滚实现，不能把设计写成已经验收。

## 第三阶段启用条件

可信发布包及元数据、经过审查的精确 manifest、当前安装归属基线、独立生命周期锁、可恢复日志及完整故障注入测试全部具备后，才另行开放安装。测试需覆盖下载失败、错误哈希、缺文件、路径／链接逃逸、本地修改、中文路径、并发运行、各种中断点、恢复失败，以及正在运行的游戏保持不受影响。当前只验证安装禁用时不会消费危险资源，不能等同于上述安装测试通过。

## English

`[11] Check for updates` uses the existing UI 2.0 controls and all ten languages. Checking is explicit and read-only. It reuses VERSION and the official public Releases API without a token or Git dependency. Stable stays stable; preview stays preview; beta/rc retain their own prerelease identifier. Main commits and tags without Releases are never treated as releases. Numeric prerelease identifiers follow SemVer ordering; build metadata does not change precedence.

No releases produces an explicit message. Other-channel-only releases, invalid metadata, an installed version ahead of releases, network/timeouts and rate limits have separate states. Requests use normal TLS verification, fixed repository endpoints, no authentication header or redirects, bounded pages and response sizes. Remote notes are inert sanitized text. Users can view online notes plus the local CHANGELOG and explicitly open the fixed official Releases page.

**Phase 1 is enabled; installation is always disabled.** The repository had no Releases when checked on 2026-10-29. No assets are downloaded, extracted or executed; no files or VERSION are replaced. ZIP/clone/moved/Chinese/space-containing folders work because checks do not depend on Git or a fixed project path. Runtime components, credentials, user data and running games are untouched.

The [managed-file draft](update-managed-files.draft.json) is an explicit design-only allowlist, not trusted ownership or an install manifest. A future installer must verify an official release/asset and a SHA-256 anchored in trusted API metadata or verified publisher signatures/attestations, not merely an unauthenticated checksum beside the same download. It must prove the current files' ownership, refuse local edits or unknown baselines, validate every archive path/file/link/hash, back up only managed files, and hand off to an independent trusted worker that waits for all launcher entries to exit.

No downloaded installer scripts, whole-directory overwrites, git pull/reset/clean, runtime-component replacement, network changes or process termination are allowed. A durable transaction journal and cautious rollback are required; recovery cannot overwrite intervening user edits or promise success after disk/power failures. Only a future separately validated release package and complete fault-injection tests can unlock installation. Download, extraction, handoff and rollback are not implemented or tested in this phase.
