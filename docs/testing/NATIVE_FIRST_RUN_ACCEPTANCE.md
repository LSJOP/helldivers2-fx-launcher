# First-run acceptance

Development scope: isolated source/build only. No current successful SteamOS changes, new VM creation, Latest replacement, main merge or release.

| Status | Result |
| --- | --- |
| IMPLEMENTED | SwiftUI wizard, real host/SSH detector, versioned profile, reviewable plan, exact consent, executor, receipts, selective safe recovery, FEX/Proton/FX/Steam/network adapter interfaces |
| VERIFIED | See docs/testing/NATIVE_DEPLOYMENT_TEST_RESULTS.md for exact isolated checks and build evidence |
| BLOCKED | Reviewed distributable FEX/Proton artifacts and clean installed-tree manifests; package/download UI activation; unsupported archive formats and version combinations |
| NOT_TESTED | Clean official FX 1.9.8 + recorded SteamOS VM; full Native deployment; compatibility tool recognition; real game/official EAC chain; independent multiplayer; live repeated install and restore |

The final ordinary-user one-click deployment acceptance is **not achieved** while required artifacts and new-VM testing are blocked. The build is a reviewable development implementation, not a production installer. Completion of approved configuration items never means that blocked components were installed. The UI retains blockers after partial success and asks for rescan.

Future live acceptance requires the user's explicit authorization and an independent official VM, without personal disk/Prefix cloning. Record initial state, exact target/profile/artifact hashes, real installation receipts, repeat behavior and recovery. Validate gameplay, official EAC and multiplayer separately. Do not substitute any local tests for these results.


## Recovery candidate · 2026-11-15

Resumed the existing `/private/tmp/hd2-fex-merge.9K0x03` worktree on
`fix/first-run-ssh-access`, HEAD `2ddd624`. All six uncommitted files were
preserved in `HD2-App-Builds/Backups/first-run-resume-20261115-225152` before
continuation. No main merge or release is authorized for this task.

Recovered work: verified local Runtime archive upload over the App-owned SFTP
master; Valve HTTPS fallback pinned to 4.0.20261021.265997; bounded extraction,
whole-tree fingerprints, registration, transaction recovery and FEX probe.
Continuation adds verified Runtime download cache/retry, explicit Debug test
resource/image arguments, and a component catalogue in
`native-app/Resources/deployment-components-v1.json`. The catalogue records exact
sizes/hashes and distribution status; it does not itself authorize installation.
The 13 RF entries comprise the 10 historical files plus emulator/tool/wrapper
integration metadata, totaling 12,733,729 bytes before auxiliary support files.
They remain outside the App. Five existing bundled metadata/license/patch files
total 1,098,307 bytes, plus the catalogue itself; these are not RF binaries.

Runtime online source: https://repo.steampowered.com/steamrt4/images/4.0.20261021.265997/
Official archive: 175,077,288 bytes, SHA-256
`aa9dd1aab2173e65b631faae34b85e2c17fe323d941013154ddd2e1dce8a0910`.
Historical depot archive: 717,803,520 bytes, SHA-256
`31a43e6e6ff78509eb1cdb762cfff8e9d89fc83c118d5d723bead42b9b18ca5c`.
The local archive has been exercised in the real App; official archive extraction
was inspected previously, but real App online Runtime download remains untested.

Live continuation: real Debug App on FX 1.9.9 / steamos-1.img. Runtime/FEX
receipt `8101D827-755B-4830-906F-A857635620ED` is completed and retains the ARM64
Runtime. After explicit custom-FEX consent the same first-run action downloaded
Proton-JE 11.0-20261014-3 from the existing upstream installer, installed it and
performed a sudo-authorized graceful Guest reboot. The saved reboot transition
confirms a new boot and reauthenticated SSH. Final verification is recorded below.

Checks: Runtime/FEX transaction 19, FEX probe 11, Proton 19, SSH 38 and deployment
156 pass; arm64 Debug build passes. Full run_checks stopped at the pre-existing
screenshot-source fingerprint gate. This task changes no Views, artwork or
localized UI strings; existing screenshot review remains pending and was not
marked PASS. No game launch or production FX 1.9.12 mutation.

Public one-click delivery remains BLOCKED: RF binary provenance and redistribution
permission are unconfirmed, the historical replay is Debug-only, and production
bundle/download activation, byte progress, online Runtime live acceptance and
full live failure/recovery matrix remain pending. Do not publish these samples or
claim a clean-computer production installer. Native Swift Core is authoritative;
the legacy Python Bridge is not reintroduced.


Final live result: **FAILED, configuration below 100%**. The App installed
Proton-JE, applied launch options and the compatibility tool through its existing
service, and verified the graceful reboot/SSH transition. Final verification
returned VERIFY_FAILED. A second real App setup attempt stopped explicitly at
FEX_KNOWN_LAUNCH_INCOMPATIBILITY. Read-only post-reboot inspection found the FEX
executable SHA-256 `f9cbb7a70e804b9930fed02fd9d1349d49d7808faace703063a9b4944bc3568e`
and emulator.json SHA-256 `431e4340dabceb76fd83733864058e1d4176fa35aecde3b8c69cafc686968774`;
the container RootFS value is empty again. Before reboot the RF transaction had
completed with FEX_ROOTFS=/ and the pinned RF executable. Both Runtime directories
remain present. The exact boot-time owner restoring these files is not yet
identified. Do not work around this by accepting the known incompatible hash,
reapplying samples blindly, or modifying production FX. Durable FEX/RootFS
integration across the required reboot is a live acceptance blocker. Manual game
launch is not recommended from this configuration. Repeat setup detected the
problem without downloading Proton again; the complete live failure/rollback
matrix remains untested.

Latest artifact: `HD2-App-Builds/Candidates/FirstRun-Recovery-20261115/HD2FXNative.app`, arm64 Debug with optimization enabled, ad-hoc deep signature validation and bundle secret scan pass. A fresh launch of this final artifact starts a process but currently exposes no main window; latest-artifact click acceptance is NOT VERIFIED. The real deployment/failure observations above came from the recovered RuntimeDebug2 App, not this final build. Do not conflate those versions. This startup issue and the pre-existing screenshot-source gate are additional open blockers. No final screenshots were fabricated or marked reviewed.


## Persistence and window repair candidate · 2026-11-15

The root cause is now confirmed by the actual Guest, not inferred from the reboot.
`findmnt -T FEX-Emu` reports `/home`, `/dev/vda8`, ext4, read-write. Steam's
`content_log.txt` records AppID 3127680 validating FEX-Emu at 23:01:05 and committing
55 updated files from `steamapps/downloading/3127680` at 23:01:06, build 24136555,
depots 3127681/6486428636716542397 and 3127682/8280186011641936150. That commit replaced
the RF executable and emulator.json. No evidence of a volatile home/overlay
reset or an FX startup script restoring the FEX directory was found.

The candidate reuses the FEX transaction at
`~/.local/share/HD2FXLauncher/compatibility/FEX-RF`, outside Steam's managed depot.
The official FEX directory remains intact. Steam launch options use the existing
compare-and-swap service to set `PRESSURE_VESSEL_EMULATOR` to that owned emulator
manifest, whose container_environment sets FEX_ROOTFS=/.
The installed Runtime binary exposes both PRESSURE_VESSEL_EMULATOR and
STEAM_COMPAT_EMULATOR. A real container invocation selected the owned FEXCompatTool
and FEXServer and checked FEX_ROOTFS=/ without launching the game. Initial probing
also produced portable telemetry/server files in the owned install, causing the
expected tree-drift rejection. That entire failed tree was retained under
`FEX-RF.hd2-probe-retained-f5368b5d-942b-4e71-9d41-5716b2bf3ddc` after identity,
receipt, original-file and generated-cache checks; the receipt records recovery.
The corrected probe uses isolated per-app data and terminates its process group
on timeout. No system startup unit, sudoers or original FEX files are changed.

Runtime read-only integrity checks now permit content-identical hardlinks created
by pressure-vessel in var/. Every distributed file is still hashed; FEX installs
retain the strict no-hardlink rule. App resource catalogue lookup canonicalizes
the bundle resource root, fixing validation when launched through /tmp aliases.
First-run readiness now uses actual FEX runtime evidence consistently.

The latest Debug opens its main window, navigates to first-run setup and accepts
real clicks. AppDelegate now requests the existing SwiftUI main scene when launch
or reopen restoration produces no visible main window, using the same AppState.
Command-N also opens that scene. Twenty current real read-only en/zh-CN viewports
were recaptured in an isolated screenshot bundle with credential autoload disabled;
they are idle UI evidence, not successful-deployment screenshots.

Live final deployment/reboot validation is still PENDING at this checkpoint:
a separate production FX process appeared at 23:27:05. The existing foreign-FX
instance guard refuses to continue. No production process was terminated and no
instance check was weakened; a normal-exit decision was requested from the user.

Distribution: the pinned upstream FEX source LICENSE is MIT:
https://github.com/StonkGuy/FEX/blob/87c57f0a5f2a0e87c6b994e9d91f72ac6d512ab8/LICENSE
The existing source-build service can fetch that pinned commit and apply the
reviewed patch. This does not yet validate historical helper binaries or all
vendored notices/reproducible outputs: BUILD_THUNKS is OFF in that service, whereas
the local sample includes thunk libraries. No historical RF binary was added to
the public bundle. Formal source-built distribution and fresh-user acceptance
remain blocked until the full dependency/notice/build chain is reviewed.

## Isolated App acceptance · 2026-11-16

The arm64 Debug App launched FX 1.9.9 and verified its process owned
`steamos-1.img`. The first click reached the RF package read on the external
volume and stalled in a host file open. This attempt was cancelled before Guest
deployment. The next App process used a private local copy of the same pinned
RF inputs. The existing App-installed SteamLinuxRuntime_4 and Proton-JE
11.0-20261014-3 were reused. SteamLinuxRuntime_4-arm64 remained present.

A real setup click deployed the RF tree outside Steam's depot, verified the RF
executable and ran the Runtime container probe with FEX_ROOTFS=/. The App applied
the per-game emulator launch option, presented the normal reboot confirmation,
reconnected after the boot ID changed, and retained the RF tree, RootFS setting,
Proton selection and launch option. The stock FEX hash remained
`f9cbb7a70e804b9930fed02fd9d1349d49d7808faace703063a9b4944bc3568e`.
The managed RF hash after reboot was
`ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf`.

Verification initially stopped on the hard-coded unknown KosmicKrisp check.
The fix reads the identity-bound FX supervisor's driver argument and checks the
Guest's Vulkan boot mode. The network check requires a successful, bounded
Steam Store TLS probe from the Guest. A cold App reopen and another real setup
click verified the persisted configuration and displayed the completed state.
The final arm64 Debug binary SHA-256 is
`8571abedc991fe5e200c60c8e665765261b76329a13299bc1a16b7df82f289be`.
No game launch or production FX 1.9.12 write occurred. This acceptance spans
installation and verification runs on the same isolated disk. A fresh-disk
single uninterrupted pass, Valve Runtime download through the real App, live
failure injection and RF public distribution are still pending.

## Audited RootFS and reboot persistence · 2026-11-16

Inputs: the [FX 1.9.12 audit and comparison at 78d03b6](https://github.com/LSJOP/helldivers2-fx-launcher/commit/78d03b6)
record the RF executable under Steam's FEX-Emu depot, nine matching installed
RF files, a stage-only VERSIONS.txt, the JE selection, the 4183110 Runtime,
the empty emulator registration and the provider-based ConfigTemplate.
Both the audited depot and the test App's managed location are on persistent
/home. The observed Steam AppID 3127680 depot replacement on FX 1.9.9 is the
reason the candidate keeps its RF tree outside that depot. The Steam copy is
preserved, and the existing game launch option selects the managed emulator.

The real Debug App migrated its exact legacy tree through the existing FEX
backup and recovery transaction. The registered value is now the original empty
string and emulator.json SHA-256 is
`431e4340dabceb76fd83733864058e1d4176fa35aecde3b8c69cafc686968774`.
The provider template remains `@FEX_ROOTFS_PATH@/`. No game prefix was created
or edited to force a RootFS value. Recovery fixtures verify restoration of
the previous registration without modifying Steam's copy.

The FX 1.9.9 test VM ran through boot prefixes `348cdd1c`, `e8a54878` and
`54ed4e07` after two normal restarts. Real App setup completed after each reboot
and skipped replacement of the existing Runtime and Proton-JE. All 18 recorded
file hashes matched across the three snapshots, including both Runtime versions,
the managed RF group, Steam's original FEX executable and Proton-JE key files.
The per-game emulator launch option and the Proton-JE selection persisted.
The second-boot no-game container probe observed the exact managed executable
`/home/steamos/.local/share/HD2FXLauncher/compatibility/FEX-RF/usr/bin/FEX`
through its process executable identity. It reported an empty RootFS environment
value in the synthetic probe. The historical game's effective container value
remains unconfirmed.

The final App opened its main window on a cold launch. A real setup click on the
second reboot displayed the verified completion panel with 100%.
The final arm64 Debug build SHA-256 for the executable is
`a0880f15315db5024587ccc3953967e0c344c45eb8df41e6dc45768918a76686`.
This was a migration and repeatability test on the existing test image. The
Runtime and Proton installation observations from the previous acceptance
remain separate. A fresh-disk, uninterrupted install on this final build and
public RF source/redistribution remain open. No game, EAC, multiplayer, production
FX, packaging or updater acceptance was performed. The current README screenshot
source gate is pending renewed visual review of the changed completion view.

## 内置 RF FEX 验收门禁 · 2026-11-16

已完成的证据继续有效：最新 arm64 Debug App 冷启动及首次配置 100%，独立 RF 持久化，两次正常重启、18 个关键文件 SHA-256 一致，Proton-JE、Runtime 和 Steam 配置保留。这些结果来自既有测试镜像的迁移和复验，未走 App Bundle 的 RF 制品输入路径。

新版混合部署方案待验收：

- [ ] 构建产物实际捆绑审核通过的 RF FEX 和对应模板。
- [ ] 验证 Bundle 路径、资源清单、文件大小和 SHA-256，并拒绝损坏资源。
- [ ] 从全新测试镜像用真实 App 自动提取、上传、部署和验证，同时完成固定 Proton-JE 和 Runtime 的下载与校验。
- [ ] 普通用户流程与备用下载均不依赖开发者本地路径或用户提供 RF 文件。
- [ ] 两次正常重启后，文件哈希、实际 FEX 加载路径、Steam 配置和已验证组件跳过逻辑保持有效。
- [ ] 在该构建上另外验收真实游戏启动，并记录结果。
- [ ] 确认 RF 及伴随组件来源、许可和再分发权限。
- [ ] 验收正式 Release 安装和应用内更新。
