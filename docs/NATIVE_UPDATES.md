# Launcher updates / 启动器更新

## Component update schema 3

Schema 3 extends the Ed25519-signed `update-manifest.json`. Sign the exact bytes with the existing update key. The signed manifest authorizes the full ZIP by exact length and SHA-256. Keep the independent whole-ZIP Ed25519 signature and 512 MiB limit for schema 2. Schema 3 caps signed, transport and installer ZIP sizes at 2 GiB. ZIP preflight also caps expansion at 2 GiB and fewer than 20,000 entries.

The inherited manifest fields carry channel, target version, increasing build number, minimum macOS version, bundle ID, architecture, source commit and full archive identity. The new `components` object carries:

| Signed field | Validation |
| --- | --- |
| `protocolVersion` and `minimumBaseBuild` | Schema 3 component protocol 1, older bases use the full ZIP |
| `targetTreeSHA256` and `targetBytes` | Complete target inventory digest and total bytes of files and symlink targets |
| `core` | Fixed current-release Core ZIP URL, exact byte length, SHA-256 and expanded size |
| `modules` | RF and Proton-JE for the current component target; legacy RF/Proton-JE/Runtime 4 sets remain readable. Each entry carries a version, fixed destination, tree fingerprint and artifact. Engine-only releases use an empty set. |
| `artifact` | Immutable GitHub repository release URL, archive length, expanded byte length and SHA-256 |

The inventory sorts relative paths by UTF-8 bytes. Each record includes path, octal mode expressed as its decimal value, type, and regular-file length and digest or symlink destination, separated by NUL bytes. The version and build select one signed combination. The target's complete code signature, nested code, expected executable, arm64, bundle identity and update trust key are mandatory. Download or assembly failure attempts the signed full ZIP once. Untrusted manifest signatures stop the update. The new target never reuses the omitted Runtime 4 directory. Core archives cannot supply any known module destination, and assembly rejects a retired Runtime path absent from the signed module set. Steam owns the Guest Runtime independently. The Helper independently verifies the staged target before exchange. Guest deployment remains separate.

Use `native-app/script/package_component_update.py APP STAGING --minimum-base-build BUILD --dmg` to prepare private staging from the already signed App. It generates a complete ZIP, Core ZIP and module ZIPs, measures sizes, reconstructs a target in scratch and checks its inventory and code signature. Use `--signing-key` for optional signing with the existing operator key after checking it matches the App trust root, or sign the exact manifest separately. `--previous` can omit unchanged published module assets after validating the earlier signed manifest and GitHub asset length/digest. The CI release verifier checks these references against their pinned release. Unapproved resources are rejected by production packaging; `--local-test` is restricted to a test identity and ignored local build directory.

Legacy clients cannot read schema 3 and cannot download ZIPs above 512 MiB. The compatibility option is an engine-only bridge under that limit published with schema 2, followed by the full target once supported. Stable v1.0.5 published a signed Schema 2 bridge alongside a Schema 3 manifest. For the next release, measure the public full ZIP and verify both feeds against the pinned update key. The legacy client’s real direct-upgrade result requires its own evidence. An approved full DMG provides the manual upgrade route when the bridge is unavailable. Preserve the existing installed App until the target identity, version and signature are verified. See [acceptance](testing/COMPONENT_UPDATES_ACCEPTANCE.md) for the tested scope.

## Current release policy / 发布规则

Development changes require proportionate tests, a commit and push, a corresponding PR update when applicable, and remote SHA verification. Ordinary verified PRs may be merged under repository rules; emergency fixes still require necessary tests. A Release is not required for each change. Preserve other work. Stable Release creation requires explicit user authorization.

Use semantic versions MAJOR.MINOR.PATCH: PATCH for fixes, UI and small compatibility changes; MINOR for backward-compatible features; MAJOR for breaking changes. Several changes may share a release. Check existing local and remote tags and Releases; never reuse a published tag. Set the App marketing version and a strictly increasing build number, and update both CHANGELOGs and both READMEs.

Before a formal release, prepare a traceable arm64 Release, DMG, ZIP, SHA-256 checksums and Ed25519-signed update metadata. Always verify version consistency, signatures and artifact integrity; never waive those checks. Reuse existing artifacts and evidence only when source, build inputs and relevant environment match. Check localization and other tests when affected, while respecting required CI. Installation, upgrade and failure recovery are the default acceptance; explicit user authorization may waive specified non-security acceptance, which must be recorded as unverified. Isolated tests never establish real App acceptance. After publication verify public URLs, signatures and channel; verify App detection where not explicitly waived and record the result. Keep prereleases out of Stable and private keys out of Git. Ad-hoc signing is accepted; Developer ID and notarization are not required.

Preserve the independent Update Helper and its verification, transactional replacement and recovery boundaries. Historical Sparkle packaging and feed material below is context, not authority to replace the Helper or a claim that production updates work. The release verification workflow is `.github/workflows/native-release-check.yml`; it checks signed artifacts and synchronizes stable README sections. Validate the current signing and distribution procedure before use; old Keychain/Developer ID commands below are historical and not a mandate to use them.

开发修改按范围测试、提交并推送；有对应 PR 时同步更新并验证远程 SHA。普通 PR 通过必要检查和仓库规则后可合并；紧急修复也须测试，每次修改不必发布。正式 Stable Release 仍需用户明确授权。

版本采用 MAJOR.MINOR.PATCH；核查远程标签，禁止复用已发布版本。发布从 main 打 Tag，更新版本、递增构建号及中英文 CHANGELOG／README。准备可追溯的 arm64 Release、DMG、ZIP、SHA-256 和 Ed25519 签名清单；版本一致性、签名和产物完整性不可豁免。代码、依赖和环境一致时复用已有产物与证据；按影响范围检查本地化和测试，并遵守必需 CI。默认完成安装、升级和失败恢复验收；用户明确授权可跳过指定的非安全验收，必须逐项标记未验证，隔离测试不能冒充真实 App 验收。发布后验证公开链接、签名和渠道；未豁免时验证 App 识别并记录结果。保持 Stable 与预发布分离、私钥不入 Git、独立 Update Helper 和既有安全机制不变；允许 ad-hoc 签名，不要求 Developer ID 或公证。

### README publishing / 首页发布

Prepare the English and Simplified Chinese changelog entries and Release Notes together. Check parity with the bilingual homepage and the standalone Chinese README. Update the highlights under their own headings during release preparation. Include each known acceptance gap, and keep development notes in the documentation archive. Recapture published App windows only when the UI or shown features change.

The existing Latest-release workflow updates only the three single-line `stable-version`, `stable-download` and `stable-build` blocks after verifying signed assets and matching changelog releases. The primary button uses the verified tag-specific DMG URL; publishing the next Latest release advances that URL. Verify both documents with `python3 script/check_docs.py` and `python3 native-app/script/check_readme_screenshots.py`. Review the rendered GitHub homepage in light/dark and at narrow width, follow the language links and confirm the DMG opens the published asset.

中英文 CHANGELOG 和 Release Notes 一起准备，并核对双语首页和独立中文版 README。发布准备时在独立标题下更新亮点，注明尚未验收的项目，开发记录保留在文档归档中。仅当界面或展示功能变化时重拍正式 App 窗口。

现有 Latest 发布工作流核对签名资源和双语 CHANGELOG 后，只同步两个 README 的三个单行标记区。下载按钮直接使用经校验的版本专属 DMG 链接，新正式版发布后随工作流更新。检查 HTML 结构、截图路径及来源、语言锚点和下载链接，并查看 GitHub 深浅主题及窄窗口的实际渲染。

## Historical update design and audit / 历史设计与审计

The following dated sections record earlier states and may be superseded by current code, the policy above and later sections. Verify live configuration and actual release status rather than treating historical statements as current.

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

The former manual readiness template was moved to `.github/workflows/native-release-check.yml` and extended for Stable release synchronization. It verifies artifacts and can update README documentation. See Stable README synchronization below for its limits. The Developer ID and Appcast preparation procedure in this historical section is separate from the current ad-hoc release workflow.

Publication order after explicit owner approval:

1. Validate the signing keys, Developer ID/notarization, HTTPS Pages service and existing feed history.
2. Prepare and review the final signed/notarized ZIP, signed JSON manifest and signed Appcast. Preserve artifact bytes and never overwrite an existing build.
3. Create a `native-v<version>` **draft Release** titled `HD2 FX Launcher v<version>`, attach ZIP + manifest + detached signature and reviewed English and Simplified Chinese notes, and mark preview as prerelease. The display title does not change the tag, signed archive name, App bundle filename or identity. Obtain explicit publication approval. This task creates no Release/tag and does not alter historical releases.
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

原手动检查模板已迁至 `.github/workflows/native-release-check.yml`，支持正式发布后的双语 README 同步及手动发布前检查。它验证发布资源、签名和版本，但不会自动发布 Release。分支保护下创建 PR 需要仓库允许 Actions 创建 PR；具体限制见文末说明。下方 Sparkle／公证材料记录历史方案，当前发行采用 ad-hoc 签名和独立 Update Helper。

References: [official Sparkle setup](https://sparkle-project.org/documentation/), [publishing and signatures](https://sparkle-project.org/documentation/publishing/), [security configuration](https://sparkle-project.org/documentation/customization/), [GitHub runner requirements](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).


## Stable ad hoc integration candidate · 2026-11-14

The v1.0.0 integration accepts strict code structure and bundle identity checks for ad hoc signing. Publisher authority continues to depend on the embedded Ed25519 key and verified signatures. The allowlisted official GitHub stable Release appcast can be used alongside the historical Pages feed. The service remains unconfigured until real public metadata and keys are ready. Archive path preflight is still a standalone policy; complete archive/install/relaunch/recovery and a real upgrade remain required before release.

正式版整合候选允许通过严格代码结构及 Bundle 身份校验的 ad hoc 签名，发布者授权仍依赖内置 Ed25519 公钥和签名。增加官方 GitHub 正式 Release appcast 入口，并保留历史 Pages 入口。真实公开元数据和公钥准备好之前，服务仍保持未配置。归档路径预检目前仍是独立策略，发布前必须完成归档、安装、重启、恢复链路及真实升级验收。


Schema 2 integration requires archiveEdSignature in the signed manifest. The verified archive must pass its independent Ed25519 signature and ZIP directory/local-name/path/link checks before caching completes. Sparkle installation is bound to that signature, URL and version. Schema 1 downloads remain supported and cannot authorize installation. Native automatic checks run only after opt-in, immediately and every six hours; Sparkle handles the approved install/relaunch. Real full upgrade and rollback tests remain pending.

第二版清单要求 archiveEdSignature。缓存完成前检查独立归档签名及 ZIP 目录、局部文件名、路径和链接；Sparkle 安装必须匹配该归档签名、URL 和版本。保留第一版清单下载兼容，第一版不能授权安装。用户启用自动检查后，原生检测立即执行并每六小时重复，Sparkle 负责批准后的安装和重启。真实完整升级及回滚测试仍待完成。

## v1.0.1 更新接续 · 2026-11-14

已整合包含品牌及 LED 的 main b789642；保留既有更新签名和 ZIP 检查。候选版本 1.0.1/build 2026111404，公钥固定在 Updates.xcconfig。独立 update_signing.swift 以仓库外 0600 文件管理私钥，不访问 Keychain，不打包到 App。原 prepare_native_release.sh 为历史 Keychain/Developer ID 路线，本轮未执行，不适用于本次无 Keychain 交付。

未完成：重复下载/确认消除、独立安装和健康确认/回滚协议、真实 1.0.1→1.0.2 升级及故障矩阵。仅配置公钥不代表服务就绪，保留服务关闭。未发布 Release、未晋级 main。截图与真实安装仍需完成，草稿 PR 必须保持未合并。

## 独立安装助手候选 · 2026-11-14

Swift 服务保留签名清单原始字节和签名，将已经下载的 ZIP 交给单一 Helper。Helper 从当前 App 读取固定公钥，用复制到私有事务目录的归档复验 SHA-256、Ed25519 和 ZIP 结构，然后提取并校验 App 签名、版本、Bundle ID 和公钥连续性。旧 App 在 Helper 提示准备就绪后正常退出。Helper 使用同卷原子交换保留旧包，新 App 主窗口可见后写出本次启动令牌。未收到令牌或进程提前退出时恢复旧包并确认其启动。事务日志保存在安装目录旁。Sparkle 运行时的安装入口移除，历史打包和框架依赖保留。

隔离测试使用临时密钥和实际 ad-hoc 签名的 AppKit 测试包，不读取正式私钥或用户数据。Helper 若被强制终止，现场、日志及交换后的旧包会保留在 .HD2FXNative-update，后续安装会拒绝覆盖。自动接管中断事务、真实启动器单击跨版本升级和用户配置保留验收仍待完成。生产服务继续关闭。

## Stable README synchronization

The GitHub Actions workflow `.github/workflows/native-release-check.yml` runs after a published Stable Release or promotion of a prerelease to Stable and offers a manual release verification entry. It checks the tag, packaged App identity and build, asset hashes, signed manifest and ZIP, changelogs, localizations and the public DMG URL. It updates the marked stable sections of both READMEs for the current Latest release. If direct push to main is rejected, the job fails with instructions to use an existing fixed branch; it does not create a branch automatically.

Run the manual workflow against a draft release before publishing. It checks that both README blocks can be updated while the current Latest download links continue to point to the existing release. GitHub does not automatically prevent a manually published release when a separate workflow fails, so the publisher must require the verification result. Releases created using the repository GITHUB_TOKEN may not trigger another workflow; use an appropriate release publisher credential or run the synchronization separately.
