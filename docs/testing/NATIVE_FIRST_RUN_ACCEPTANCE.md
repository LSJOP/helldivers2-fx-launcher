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
