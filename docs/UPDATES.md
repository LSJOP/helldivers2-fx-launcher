# 在线更新 / Online updates

[README](../README.md) · [版本规则 / Versioning](VERSIONING.md) · [更新日志 / Changelog](../CHANGELOG.md) · [用户数据保护](USER_DATA.md) · [阶段 B 安装设计](UPDATE_INSTALL_DESIGN.md)

## 阶段 A：当前已经可用

主菜单 `[11] 检查更新` 打开 UI 2.1 更新中心。**进入页面不联网**，初始显示“尚未检查”；只在用户选择 `[1] 检查最新版本` 或失败页 `[1] 重试` 时请求 API。启动器启动和游戏启动不自动检查。

```text
检查更新 / UPDATE CENTER
  当前版本 / 当前通道 / 最新版本 / 发布时间 / 状态
  发布附件元数据 / 自动安装状态 / 更新摘要

  [1] 检查最新版本
  [2] 安装更新（尚未开放）
  [3] 查看更新日志
  [4] 切换更新通道
  [5] 打开 GitHub Releases
  [0] 返回主菜单
```

只读摘要和操作共用现有 UI 2.1 组件；小窗口优先保留操作。长更新日志可滚动。`[3]` 不联网即可查看本地 CHANGELOG；查询成功后也展示该 Release 的正文。远端正文只作为清理过转义/控制字符的文本，不执行 Markdown、Shell、HTML 或其中的链接。`[5]` 仅打开固定的[官方 Releases 页面](https://github.com/LSJOP/helldivers2-fx-launcher/releases)。

### 版本、通道和真实状态

唯一版本源为根目录 [VERSION](../VERSION)。使用匿名官方 [List releases API](https://docs.github.com/en/rest/releases/releases#list-releases)：`/repos/LSJOP/helldivers2-fx-launcher/releases`。不读取本机 Token，不要求 GitHub 登录、gh 或 Git。main 提交及没有关联 Release 的普通 Tag 不作为发布版本。

比较保留现有 [SemVer](https://semver.org/) 实现：数字预发布编号按数字比较，构建元数据不改变先后顺序。正式版本默认 Stable，当前预览版本默认 Preview；beta/rc 等保留其原首个预发布标识。Preview 和 Stable 独立，不自动跨通道。`[4]` 只改变当前更新页面的通道并恢复“尚未检查”，之后按 `[1]` 查询；不写设置，不覆盖 VERSION，不自动联网。退出页面后仍从本地版本推导默认通道。

状态区分：发现新版本、已是最新、本地领先、空 Release 列表、当前通道无版本、异常元数据、超时/断网和 HTTP 错误。**查询失败不会显示成没有更新**。草稿、非 SemVer、无有效日期及标签/预发布标记不一致的条目不作为候选。

查询成功后显示当前/最新版本、通道、UTC 发布时间、正文摘要和附件情况。附件显示“可识别 / 声明”数量：前者只表示官方 URL、ID、名称、大小及 uploaded 状态等展示级格式匹配，不代表已经下载或验证安装包。缺少附件字段显示未知。GitHub 自动生成的源码 ZIP/tarball 不自动视为安装包。

即使有新版本、附件和 digest，也保持 `[2]` 禁用，并提示“发现新版本，但当前仅支持前往 GitHub 下载”。目前没有已验证的兼容安装包识别/安装能力。

### HTTP 403 / 429

遵循 [GitHub 限流建议](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#handle-rate-limit-errors-appropriately)，但不要求或读取 Token：

- HTTP 429 或 HTTP 403 且 `X-RateLimit-Remaining: 0`，标记为有证据的限流。
- 普通 403 显示“API 请求受限或访问被拒绝”，不单凭状态码认定限流。只有 Reset 或剩余额度大于 0，不能证明额度耗尽。
- 解析 `Retry-After` 秒数/HTTP 日期和 `X-RateLimit-Reset` UTC epoch。合法等待提示在本更新页面内保存在内存，用户提前重试不会发出请求；切换通道也不会绕过等待。
- 无可靠恢复时间的已确认限流，采用至少一分钟的本地等待，并明确它不是服务器恢复预测。无效、重复、过期或不合理的时间值不用于伪造恢复时间。
- 失败页提供 `[1] 重试`、`[2] 打开 GitHub Releases`、`[0] 返回`。重试始终由用户选择；没有后台重试、换 IP、改代理或认证绕行。

请求继续使用默认 TLS 验证、固定仓库 API、无认证头及拒绝重定向；分页只接受本地构造的官方地址。每次 socket 超时 8 秒、最多 5 页、每页最多 1 MiB。HTTP 404 不是空 Release。断连、不完整响应、异常 JSON、深度/大小/分页超限均安全返回。错误结果仅保留允许的数值元数据，不输出原始响应正文、Cookie、代理地址或凭据。

### 本次真实观测

2026-10-30 04:21:30（Asia/Shanghai）匿名请求返回 HTTP 403：服务器报告限额 60、剩余 0，并给出重置时间 **2026-10-30 04:42:43 +08:00**；响应消息也属于额度耗尽。请求使用正确 Accept、API Version 和 User-Agent；没有 Authorization。系统查询未发现显式 HTTP/HTTPS 代理，响应未见代理拒绝标记。证据指向匿名配额耗尽，不能证明所有中间网络层均不存在。

该时间是服务器当时报告的重置时间，不保证之后一定恢复；没有等待后自动重试。本次无法确定最新版本/当前 Release 数量。2026-10-29 的 0 项仅为历史观测，不能据此描述当前状态。没有创建 Release 或 Tag。

## 阶段 B：安全安装设计，尚未实现

**实际文件替换清单为空。** 当前没有下载、解压、独立更新进程、备份替换、配置迁移或回滚执行器。现有 [只读保护](USER_DATA.md) 与 [逐文件候选清单](update-managed-files.draft.json) 保留；候选清单没有可信哈希和安装归属证明，不能拿来直接覆盖。

完整设计、发布资产/平台与版本绑定、磁盘空间、私有权限保留备份、退出交接、事务日志、配置无损迁移和故障注入矩阵见 [UPDATE_INSTALL_DESIGN.md](UPDATE_INSTALL_DESIGN.md)。只有可信包、精确 manifest、当前安装归属、独立执行器、回滚与全部隔离验收具备后才另行开放安装。

永远排除用户设置、SSH/Keychain/私钥、语言/外观偏好、性能/网络配置、诊断历史、未知/新增数据、本地备份和用户改过的脚本，以及 FX/FEX/Proton-JE/gvproxy 二进制、Steam 和游戏。没有全目录覆盖、git pull/reset/clean、删除未知文件或执行远程安装脚本。

本轮 Mock 测试证明阶段 A 的只读行为、限流/取消/失败状态、元数据筛选和既有拒绝替换规则，**不证明已经成功安装、迁移或回滚**。

## English

`[11]` opens the UI 2.1 update center **without a request**. `[1]` explicitly checks, `[2]` stays disabled, `[3]` reads online/local changelogs, `[4]` selects a session-only channel, `[5]` opens official Releases, and `[0]` returns. Switching resets the displayed candidate and requires `[1]`; it never saves settings or VERSION. Checking remains anonymous, manual and read-only.

VERSION, SemVer, channel isolation, fixed official endpoint, TLS and bounded request rules are retained. Main commits and ordinary tags are not Releases. Empty results, no channel candidate, invalid metadata, older/newer releases, network/timeouts and HTTP errors have distinct states. Failures are not treated as no updates. Notes are inert sanitized text. Attachment counts describe recognizable metadata versus declared entries; they do not establish package compatibility, authenticity or installability. Source archives are not installers. New releases still require manual GitHub download.

403 is a generic access denial unless the remaining quota is zero; 429 establishes rate limiting. Valid Retry-After/Reset hints are honored in memory, including across channel changes in this page. A missing reliable recovery time uses an explicit local minimum wait, not a fabricated server estimate. Duplicate/malformed/past timing headers are not trusted. Retries require user action. No tokens, automatic retries, proxy changes or bypasses are used. Error views offer Retry / Releases / Back.

The live anonymous check on 2026-10-30 04:21:30 +08:00 returned 403 with quota 60, remaining 0 and reported reset 04:42:43 +08:00, corroborated by the response-message category. No Authorization or explicit HTTP/HTTPS proxy was detected. This supports quota exhaustion; reset time does not guarantee availability and release status remains unknown. No automatic retry or Release creation occurred.

**Installation is not implemented or enabled.** The actual replacement list is empty. The [Stage B design](UPDATE_INSTALL_DESIGN.md) specifies source/asset/platform/version trust, exact ownership manifests, disk space, private permission-preserving backups, an independent worker, durable transactions, separate lossless config migration and fault-tested rollback. The candidate allowlist is not trusted ownership. User data/runtime components and locally edited or unknown files are protected. Current tests establish read-only preservation/refusal, not successful installation or rollback.
