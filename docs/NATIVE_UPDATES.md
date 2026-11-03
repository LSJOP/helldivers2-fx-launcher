# Launcher updates / 启动器更新

HD2_NATIVE_APP_UPDATE_SYSTEM_V1 **v1.0.0**, 2026-11-03. **Partially complete: manual release checking and verified-download implementation are available; live signed distribution and end-to-end installation are not ready.**

## Current audit

- Anonymous GitHub Releases API for `LSJOP/helldivers2-fx-launcher` returned **[]**. No Native release, ZIP, manifest or signature is currently published. The Actions API returned zero workflows before this task.
- Built Native bundle: `CFBundleShortVersionString=0.1.0`, `CFBundleVersion=1`, identifier **com.lsjop.helldivers2fx.native.phase1**. Native version identity comes from its own Bundle; the archived Python `VERSION` is a separate product/version source.
- Debug artifact is linker ad-hoc signed, has no Developer ID / Team ID or distribution seal. `security find-identity -v -p codesigning` found **0 valid identities**. No notarized distribution artifact is demonstrated.
- Official **Sparkle 2.10.1** was already pinned via SPM and remains the only installer. Public key/feed are empty and service/distribution flags are disabled. There is no working auto-install service to claim.
- This task shares the performance V2 branch and localization/design system, with a separate commit. Neither module calls the other. No FX, Guest, Steam, game, EAC, SSH, performance settings or user logs are changed by update code.

## Check, download and install boundaries

Settings and the App menu share `AppUpdateManager`. Settings shows separate version/build, Stable channel, last attempted check time, actual state, automatic-check preference, notes and available actions. **Manual checks work before Sparkle distribution is configured** and run only when requested. They use anonymous HTTPS GitHub Releases, without tokens/cookies or credentials, up to five bounded pages of 100. An incomplete response, HTTP failure/rate limit, malformed metadata or missing resource is an error, never “up to date”. An empty eligible list means “no Native release published”, not latest-version confirmation. Only `native-v<SemVer>` Releases count; branches/commit ZIPs, drafts and old script releases are excluded. Stable excludes prereleases.

Each eligible release must contain:

1. `native-update.json`: schema 1; exact Native bundle ID, semantic version, positive global build number, stable/preview channel, `macOS`, `arm64` or `universal`, minimum OS, ZIP name/size and SHA-256.
2. `native-update.json.sig`: base64 raw Ed25519 signature over the **exact manifest bytes**, produced by official Sparkle `sign_update -p` using its existing Keychain signing account.
3. `HD2FXLauncher-<version>.zip`: the single Native App archive, size <=512 MiB, matching the signed manifest and official repository release asset path.

When no public key is configured, release metadata may be shown for inspection but is **unverified**, and download/installation remain disabled. A wrong signature with a configured key is an explicit verification failure. Marketing version must not decrease and build must increase to offer an upgrade. Platform/architecture/minimum OS are checked before downloading.

The separate **Download verified archive** action downloads only a signature-verified candidate after user initiation. It accepts HTTPS official repository assets and GitHub's signed asset CDN redirects, bounds download size, checks available space, supports cancellation, streams SHA-256 verification and stores only the verified ZIP in private 0700/0600 App cache under `~/Library/Caches/Helldivers2FXLauncher/VerifiedUpdates`. It never extracts/executes the archive or replaces an App. Download failure leaves the installed App untouched. Live download is currently unavailable because no trusted key or published package exists; fixture signatures/checksums are not production trust evidence.

**Download and install** remains disabled unless all gates pass: valid pinned HTTPS Pages feed/public key, distribution-ready build marker, actual Developer ID signature with hardened runtime, no active Core worker and writable App parent directory. The official Sparkle UI then owns consent, archive/feed signature validation, compatible App replacement and relaunch. Only ZIP application updates from the official repository are permitted; installer packages and version/build downgrades are rejected. No arbitrary shell, downloaded script, manual App replacement or administrator request is implemented. Recheck permissions just before accepting an update; unsupported write locations fail closed. Installation/relaunch failures are separate from download success. Closing an update cycle never establishes installation or successful post-update launch.

The real signed-feed download→install→restart→version confirmation/recovery path has **not** been exercised. Do not claim it works end to end until two isolated signed builds demonstrate it. Existing user configuration/logs/runtime data remain outside the App bundle; Sparkle replaces only the Launcher.

## Channels, consent and configuration

Stable is the default on every launch. Preview is hidden until an explicitly verified preview publishing service is configured in a trusted distribution build. Switching the channel only resets update selection; it never installs. Automatic checks remain disabled before the signed service is ready; Sparkle owns first-run consent and its preference afterwards. Automatic installation is disallowed with `SUAllowsAutomaticUpdates=false`.

Use ignored `native-app/Config/UpdateSigning.local.xcconfig` only after configuring and validating the real service:

```xcconfig
HD2_UPDATE_ENABLED = YES
HD2_UPDATE_CHANNEL = stable
HD2_UPDATE_PUBLIC_KEY = <actual public Ed25519 key only>
HD2_UPDATE_FEED_URL = https:/$()/lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml
HD2_UPDATE_PREVIEW_READY = NO
```

The slash escaping prevents xcconfig treating `//` as a comment. Never insert a private key/password. The release-preparation script sets `HD2_UPDATE_DISTRIBUTION_READY=YES` for the Developer ID Release archive only, then must complete notarization/stapling/assessment before returning distributable output. This marker alone never bypasses runtime signature checks. Feed signatures and pre-extraction archive signatures are mandatory (`SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`); signed-feed failure expiration is zero so verification cannot silently relax over time.

Stable feed: `https://lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml`. Preview feed: corresponding `/preview/appcast.xml`, selected only after Preview readiness. These are planned endpoints, **not verified live services**. Do not enable flags merely because a URL/key has the right shape.

## Release preparation and approval gates

Three independent requirements remain: a real Sparkle Ed25519 key, Apple Developer ID Application identity/team, and a notarization Keychain profile. On a trusted signing Mac, deliberately run official `generate_keys` once; it retains the private key in the login Keychain. Keep a protected off-repo backup. Only the public key goes into App config. This task generates no real release key and touches no existing signing/SSH Keychain items.

The existing operator-only script is extended, rather than replaced:

```sh
native-app/script/prepare_native_release.sh \
  "$NEXT_VERSION" "$NEXT_BUILD" "$CHANNEL" "$TEAM_ID" \
  "$DEVELOPER_ID_APPLICATION" "$NOTARY_PROFILE" \
  "$RELEASE_NOTES_MD" "$NEW_STAGING_DIRECTORY" "$CURRENT_PUBLISHED_APPCAST"
```

It requires explicit version/global positive build and stable vs prerelease consistency, builds a Developer ID Release archive, checks the actual Bundle identity/feed/key, verifies code signatures, notarizes/staples/assesses, creates the symlink-preserving ZIP, generates/signs the manifest and uses pinned official `sign_update` / `generate_appcast`. It freezes the supplied historical Appcast into staging and verifies that snapshot with the matching Sparkle signing identity before reusing or re-signing any history. Unsigned/tampered/wrong-key history, mixed channels, duplicate/non-increasing builds, foreign or mismatched archive URLs, package installers and missing archive signatures stop preparation. Even an initial empty bootstrap Appcast must be explicitly signed by the trusted key. The final enclosure URL must exactly match the requested version and ZIP. It verifies archive/feed/manifest signatures, sizes and retained monotonically increasing feed history. Delta generation is disabled. Initial feed bootstrapping also requires a signed, verified service; local empty feed scaffolding is not an online update source. The script has been syntax/helper tested; full preparation remains blocked by missing signing/notarization/service credentials.

New `.github/workflows/native-release-check.yml` is **workflow_dispatch only**, main-only, read-only repository permission and no secrets/publication commands. It validates explicit release identity, selects an available Xcode 26 on an Apple Silicon macOS runner, builds Debug and runs isolated/secret checks. It records readiness, never signs or publishes. The workflow is source-reviewed/local-checked, **not remotely executed**; it becomes dispatchable only after explicit main integration. Signing/notarization remain operator steps until a protected signing environment is configured. No scheduled workflow, Release trigger or automatic publication is added.

Publication order after explicit owner approval:

1. Validate the signing keys, Developer ID/notarization, HTTPS Pages service and existing feed history.
2. Prepare and review the final signed/notarized ZIP, signed JSON manifest and signed Appcast. Preserve artifact bytes and never overwrite an existing build.
3. Create a `native-v<version>` **draft Release**, attach ZIP + manifest + detached signature and notes, mark preview as prerelease. Obtain explicit publication approval. This task creates no Release/tag.
4. Publish approved assets, verify public URLs/size/signatures, then publish the signed Appcast to its channel. Never reference drafts/missing assets in the stable feed. Repository Pages/settings remain unchanged here.
5. In an isolated App/data environment, verify check/consent/download/signature rejection/installation/restart/current Bundle version and retained settings/logs; test failure recovery before calling auto-update production-ready.

## Localization, tests and data

All update settings/status/error/notes/channel labels use the existing ten-language Native catalogs, including Chinese/English/Japanese. No English fallback is counted as translation. Standard macOS and Sparkle UI follow their own Bundle localization after App restart; no global language/menu-tree changes are made. Sparkle's bundled translations remain framework-owned.

Tests use mock GitHub responses, ephemeral in-memory Ed25519 keys, fake archive bytes and unique temporary preferences/cache directories. They cover version/build checks, available/up-to-date/empty releases, network/metadata/resource/signature/platform errors, cancellation, verified cache, corruption, Sparkle download/install/permission errors, disabled trust/channel/automatic gates and language coverage. No real App is replaced. Original performance V2 checks remain independent. Human interactive UI and a real production upgrade remain NOT_TESTED.

Secret gates retain index/Release App/ZIP/feed scanning via `check_release_secrets.py`. No private key, token, password, user configuration or raw sensitive log belongs in Git or release artifacts. Existing credentials remain owned by SessionCredentialManager in the separate Native Keychain namespace; update code never reads them. Logs/configuration and FX runtime remain external and untouched.

## 简体中文

本任务为**部分完成**：手动检查 GitHub Releases 已可用，安全下载后端已通过隔离签名与校验测试；真实签名发布、自动检查服务、安装及重启后版本验收仍受外部条件阻塞。当前仓库没有 Release，没有可下载正式更新包；本机没有有效 Developer ID 签名身份。

在「设置 → 软件更新」查看版本／构建号、稳定渠道、上次检查和真实状态，点击「检查更新」。无发布、网络错误、资源缺失、不兼容和签名错误分别显示，不伪装为已是最新版本。默认 Stable，未验证预览发布机制前不开放 Preview；服务就绪后的自动检查授权由 Sparkle 管理，不允许自动安装。

真实发布需同时提供 JSON 更新清单、其 Ed25519 签名和 Native ZIP。未配置可信公钥时不允许下载；通过签名、大小和 SHA-256 验证的包只进入私有缓存，不解压、不执行、不替换 App。只有可信 Developer ID 分发包、签名 Appcast、实际公钥、分发就绪配置及写入权限等条件均通过时才交由 Sparkle 安装；不请求管理员权限。原配置／日志、性能设置、FX、Guest、Steam、游戏及 EAC 均不修改。

新增手动触发、只读权限的 Actions 构建检查工作流，不签名、不发布、不创建定时任务。原发布准备脚本已扩展清单生成与签名；历史 Appcast 先冻结并使用匹配密钥验签，再校验渠道、构建顺序及精确资源地址，未签名／篡改／错误密钥均中止，首次空白源也必须明确签名。仍需操作者主动运行、Developer ID、公证配置和正式更新源。GitHub Release 必须先草稿审阅并获得批准，再发布附件，最后发布签名 Appcast；本次没有执行这些发布步骤。更新下载成功、安装完成、重新启动和新版本运行须独立验收。十语言文案已同步，真实生产升级仍未验证。

References: [official Sparkle setup](https://sparkle-project.org/documentation/), [publishing and signatures](https://sparkle-project.org/documentation/publishing/), [security configuration](https://sparkle-project.org/documentation/customization/), [GitHub runner requirements](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
