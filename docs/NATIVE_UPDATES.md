# Launcher updates / 启动器更新

[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

## English

**Code integrated; service not configured; end-to-end update unverified.** Sparkle 2.10.1 is pinned through SPM. `AppUpdateManager` owns the standard Sparkle controller for the current Launcher bundle. It has no FX, Guest, SteamOS, EAC or Python update hooks. Settings and the application menu share this manager. When configuration is absent, checks are disabled; no network request or “up to date” result is fabricated.

### Configuration and consent

`native-app/Config/Updates.xcconfig` defaults to disabled with empty feed/public-key values. No placeholder download URL is configured. Once the real service is ready, use the ignored `native-app/Config/UpdateSigning.local.xcconfig` to set:

- `HD2_UPDATE_ENABLED = YES`
- `HD2_UPDATE_CHANNEL = stable` or `preview`
- `HD2_UPDATE_PUBLIC_KEY` = the actual base64 Ed25519 public key, never the private key.
- `HD2_UPDATE_FEED_URL` = the verified HTTPS Pages address matching the channel. In xcconfig, encode the slash pair as `https:/$()/lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml` (or `preview`) so `//` is not parsed as a comment.

The intended Pages addresses are **not verified as live services**. The Pages API returned 404 during development; enable/verify Pages manually with repository-owner approval. The manager accepts only these repository Pages paths and a 32-byte public key. Keep automatic checks unset initially: Sparkle owns first-run consent and preferences. Automatic downloads are off by default. Both archives and feeds require Sparkle signatures; `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are enabled. Never disable these gates to test an unsigned build.

### Three separate trust requirements

1. **Sparkle EdDSA:** use the official `generate_keys` tool once, explicitly, on a trusted signing Mac. It stores the private key in the login Keychain. Keep a protected backup outside Git. Only its public key belongs in App configuration. Do not export the private key into the repository, App, README or CI logs.
2. **Developer ID:** obtain a valid Apple Developer ID Application identity and matching team. None was found on this development machine; the current Debug binary is ad hoc signed, not a distributable update.
3. **Apple notarization:** configure a `notarytool` Keychain profile, submit the signed archive, staple and validate. No notarized Native artifact has been demonstrated.

### Operator-only release preparation

The preparation script is not run automatically and does not publish anything:

```sh
native-app/script/prepare_native_release.sh \
  "$NEXT_VERSION" "$NEXT_BUILD" "$CHANNEL" "$TEAM_ID" \
  "$DEVELOPER_ID_APPLICATION" "$NOTARY_PROFILE" \
  "$RELEASE_NOTES_MD" "$NEW_STAGING_DIRECTORY" "$EXISTING_APPCAST"
```

Use a real semantic version, a globally increasing positive build number and an existing feed. Stable versions must be final; preview versions must have a prerelease suffix and are emitted on the `preview` Sparkle channel. Stable and preview feeds are separate; promote a stable release to preview users by deliberately preparing/maintaining that feed too. Do not change an existing build's archive or rewrite published feed history.

The script archives a **Release** build, requires Developer ID, validates the bundled feed/key, notarizes/staples, creates a ZIP containing only the Launcher `.app`, verifies the Sparkle signing key matches the bundled public key, then uses official `sign_update` and `generate_appcast`. Release notes are embedded from the supplied Markdown. It verifies feed signature, enclosure size/signature, channel and retained history. Delta generation is off. Tools come from the resolved Sparkle package, not third-party downloads. This flow is prepared and syntax-checked, **not exercised without signing credentials**.

### Publication order (manual, approval required)

1. With owner approval, prepare a GitHub Pages publishing source containing the `updates/` tree. No workflow or repository setting was changed by this task. With a token lacking `workflow`, configure Pages or upload through an existing approved mechanism rather than repeatedly trying to create Actions.
2. Sign and publish an initial feed only after generating the real key; the checked-in empty XML files are unpublished scaffolding, not a working service. Verify HTTPS, MIME/response and signatures before enabling the App's configuration.
3. Prepare the signed/notarized package with the script. For subsequent versions, supply the **current published appcast**, not a stale local copy. Review the retained history and notes.
4. Create a **draft** GitHub Release tagged `native-v$NEXT_VERSION`, attach the final ZIP, and review it. Mark preview releases as prereleases; stable releases must not carry that flag. Publish only with explicit authorization. Never upload a branch ZIP or unsigned Debug `.app` as an update.
5. Verify the final public asset URL and byte size, then publish the generated signed appcast to the matching Pages path. Do not point a public feed at private/draft/missing assets. Commit the exact signed XML when tracking it; do not hand-edit a signed feed afterward. Keep previous entries/assets.
6. On a separately installed older signed version, explicitly validate check → download → signature verification → installation → restart and retained settings. Only then mark end-to-end updating verified. No live upgrade is claimed now.

### Language, data and recovery

English/Simplified Chinese standard macOS menus use bundle localization and the App's own `AppleLanguages` preference. The interface can change immediately; **restart the App for standard menus and Sparkle dialogs**. No system-wide language is changed and no menu-tree translation is performed. The visible name is consistently HELLDIVERS 2 FX Launcher; internal executable/bundle ID remain stable.

User configuration and diagnostic files remain in `~/Library/Application Support/Helldivers2FXLauncher`, outside the bundle. The Python interpreter choice and App language are saved in the existing App UserDefaults domain; appearance and runtime-root selection remain session-only. Session-only logs stay in memory and are not historical log storage. Core recovery receipts may remain in the user-selected legacy directory. No destructive data migration was performed. Replacement/relaunch waits for an active Bridge worker to finish; App termination still reaps workers. No user settings, FX installation or selected runtime is part of the update ZIP.

Official references: [Sparkle setup](https://sparkle-project.org/documentation/), [SwiftUI integration](https://sparkle-project.org/documentation/programmatic-setup/), [publishing](https://sparkle-project.org/documentation/publishing/).

<a id="简体中文"></a>

## 简体中文

**代码已集成，更新服务未配置，端到端更新未验证。** SPM 固定 Sparkle 2.10.1；`AppUpdateManager` 管理当前启动器包的官方更新控制器，菜单与设置共用。没有 FX、Guest、SteamOS、EAC 或 Python 更新接口。未配置时禁用检查，不联网，也不伪造“已是最新版”。

### 配置与授权

`native-app/Config/Updates.xcconfig` 默认禁用，Feed 和公钥为空。正式服务准备好后，在 Git 忽略的 `UpdateSigning.local.xcconfig` 中填入实际启用开关、stable/preview 通道、Ed25519 公钥和对应 Pages HTTPS 地址。xcconfig 中地址需写为 `https:/$()/lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml`（或 preview），避免 `//` 被解释为注释。

这些目标地址**尚未验证为在线服务**，本次 Pages API 查询返回 404，需仓库所有者批准后手动启用/核实。管理器仅允许本仓库对应 Pages 路径及 32 字节公钥。首次自动检查授权及偏好由 Sparkle 管理，不预设开启；自动下载默认关闭。启用 `SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction`，要求 Feed 与更新归档签名，不得关闭保护来测试未签名包。

### 三种独立条件

- **Sparkle EdDSA**：在可信签名 Mac 上主动执行官方 `generate_keys`，私钥保存在登录钥匙串，受保护备份放在 Git 之外。只将实际公钥写入配置；私钥不得进入仓库、App、README 或 CI 日志。
- **Developer ID**：需要有效 Developer ID Application 及对应 Team。本机没有找到有效签名身份，当前 Debug 仅临时签名，不能作为正式更新包。
- **Apple 公证**：准备 `notarytool` 钥匙串配置，提交、装订并验证。本次没有可证明完成公证的 Native 产物。

### 发布准备及顺序

上方命令调用 `prepare_native_release.sh`，它只准备本地产物，不自动发布。使用真实语义版本、跨通道递增的正整数构建号和当前正式 Feed；stable 不带预发布后缀，preview 必须带后缀并使用 preview Sparkle 通道。两个 Feed 分开维护，向预览用户推广稳定版也需主动维护其 Feed，不重写已有构建包或历史。

脚本构建 Release，检查 Developer ID、目标 Feed/公钥，公证并装订，仅将启动器 `.app` 打包，验证钥匙串签名公钥与包内公钥一致，再调用官方 `sign_update` 和 `generate_appcast`，嵌入 Markdown 更新说明，检查签名、大小、通道及历史保留；关闭差分包生成。工具来自固定 Sparkle 包。当前仅完成准备与语法检查，缺少签名凭据时未实际执行。

1. 经所有者批准配置包含 `updates/` 的 GitHub Pages 源。本次不修改仓库设置或 Actions；token 缺少 workflow 时使用已批准的发布方式，不反复尝试创建工作流。
2. 生成真实密钥后签名初始 Feed，验证 HTTPS 和签名再启用 App 配置。仓库内空 XML 只是未发布脚手架，不是可用服务。
3. 使用脚本准备包；后续版本必须传入当前在线 Feed，不能使用过时本地副本。核对历史和更新说明。
4. 创建 `native-v$NEXT_VERSION` 的 GitHub Release 草稿并附最终 ZIP，审阅后获得授权再发布。预览版标为 prerelease，稳定版不标。不得使用分支 ZIP 或未签名 Debug 构建。
5. 验证正式附件公开 URL 和大小，再将生成的签名 appcast 发布至对应 Pages 路径。不能指向草稿、私有或不存在的附件；跟踪签名 XML 时原样提交，不手动修改。保留既有条目和附件。
6. 从另行安装的较旧签名版本验证检查、下载、签名、安装、重启和设置保留，完成后才能声明端到端更新正常。本次未执行实机升级。

### 语言与数据保护

英文/简体中文系统菜单采用 Bundle 本地化和本 App 的 `AppleLanguages` 偏好。内部界面可以即时切换，标准菜单及 Sparkle 对话框**需要重启 App**，不改全局语言，不遍历翻译菜单树。可见名称统一，内部可执行文件及 Bundle ID 保持稳定。

配置和诊断仍在包外 `~/Library/Application Support/Helldivers2FXLauncher`。Python 选择和语言保存在原 App UserDefaults 域；外观、运行目录仍为会话偏好。会话日志只在内存中，不冒充历史日志存储。恢复记录也可能位于选定旧目录，未执行破坏性迁移。更新替换/重启等待活动 Bridge worker 结束，退出仍回收 worker。更新 ZIP 不包含用户配置、FX 安装或选定运行环境。

官方资料见上方 Sparkle 链接。
