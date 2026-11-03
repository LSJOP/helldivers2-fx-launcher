# Native sudo candidate integration validation

Date: 2026-11-04 (Asia/Shanghai). Candidate source: `1188d59f9ff130dbb55cd552a375e59423464f5f`; clean working tree at build start. Candidate-only task; no Latest replacement, main merge or rollback deletion.

## Candidate artifact

- App: `/Volumes/Thunderbolt2TB/HD2-App-Builds/Candidates/1188d59-sudo-validation-20261104/HD2FXNative.app`
- Version/build retained from source: `0.1.0 / 2026110402`; Core `1.0.2`. This candidate must be distinguished by full commit and path, not build number alone.
- Embedded source commit: `1188d59f9ff130dbb55cd552a375e59423464f5f`, source_dirty=false.
- Build time: `2026-11-03T20:39:27+00:00` (2026-11-04 04:39:27 Asia/Shanghai).
- Executable SHA256: `d386a2a7ec173ef869dc20a4dac7082814358cd8fb8eeee3c369129f4dad49f9`.
- Bundle SHA256 using the existing publisher manifest algorithm: `ab09d69ff14d8885115dc2397e5fdd98e9e73f37546759fe08f5de24a96bb055`.
- Isolated build directory: `/Volumes/Thunderbolt2TB/HD2-App-Builds/.Build-Work/sudo-candidate-1188d59-20261104`.
- Fresh Release build: PASS. arm64, Bundle ID, icon, assets, ten languages, networking-resource hashes, no Python/Bridge, embedded clean-source metadata, and ad hoc signature verification: PASS.
- Candidate LaunchServices startup and exact process path: PASS (PID 73541 at inspection). Visual About/UI and password-input acceptance: NOT TESTED by agent; computer-use tools unavailable.

The running FX networking backend originates in Latest. For this validation process only, launch used `HD2FX_LAUNCH_RESOURCES` pointing to that existing hash-verified resource directory, so the original exact-path host identity checks can examine the already-running FX without restarting/reconfiguring it. Candidate resources are independently packaged and verified, but use of this process-only override means independent candidate-owned FX startup is NOT TESTED. Credential autoload was disabled through launch arguments; user was instructed to leave both remember checkboxes off. No secret was supplied via argv/env/files/logs. No production defaults or Guest configuration were changed by the validation tooling.

## Evidence and status

| Check | Result | Evidence/limit |
| --- | --- | --- |
| FX detection | PASS | Existing FX 1.9.8 supervisor/VM and gvproxy processes observed |
| User terminal SSH + sudo | PASS (user supplied evidence) | `sudo -v && sudo -n true` in one TTY session returned SUDO_CHECK_OK |
| Quoted empty prompt | PASS | Prior live comparison: original argv produced sudo usage; fixed command produced expected no-password challenge; fixed exact command retained in 1188d59 |
| SSH/sudo classification | PASS (targeted tests) | 26 checks include SSH regression, missing credentials, explicit authentication rejection, policy denial, malformed command and timeout; no full suite repeated |
| Full Guest identity, previous investigation | PASS (previous live evidence) | Exact host/FX/gvproxy/peer plus Guest boot/marker verified before this task |
| Full Guest identity, current candidate session | NOT TESTED | Existing SSH master absent; current read-only harness stopped with ssh_master_unverified before any Guest command |
| Candidate secure password entry/authentication | NOT TESTED | Requires user interaction with candidate secure fields; user terminal success is not candidate UI proof |
| Sudo reuse across separate SSH commands | NOT TESTED | Same-session TTY success does not establish non-TTY cross-command timestamp reuse |
| Credential status UI | NOT TESTED | Source emits authenticated after successful validation, but actual candidate display is unverified |
| CheckingCompatibility complete | NOT TESTED | Read-only live preflight could not run without a current authenticated identity-bound master |
| Game launch | NOT TESTED | No candidate game launch requested while configuration/identity preflight was incomplete |
| Game menu/playability/EAC/multiplayer | NOT TESTED | No inference from Steam or game processes |

The current fresh live harness failure is an absent/unverified SSH master, not a sudo password rejection. The harness was run without passwords and did not attempt to bypass authentication. It did not execute compatibility transactions, sudo, Steam start or game launch.

## Configuration boundary and remaining issues

Source audit confirms CheckingCompatibility calls ensureIPv4. If any of the four Guest `/proc/sys/net/ipv6/conf/{all,default,eth0,lo}/disable_ipv6` values is not 1, that function runs a privileged write before continuing to Steam/game. This changes runtime Guest network configuration (not persistent sysctl files), and can alter Guest IPv6 connectivity. It has not been authorized or executed in this candidate task. Before any such test: establish the identity-bound connection, read/record all four original values, explain the exact differences, obtain user confirmation, and retain a restore procedure for only those four values on the same verified Guest boot. Do not claim rollback safety without recording the actual original values.

Another unresolved acceptance concern is separate SSH invocations for sudo verification and the subsequent sudo -n transaction: timestamp policy may require new authorization. Do not change sudoers, password policy, or global timestamp settings to make the test pass. Validate current policy through harmless authorization-only checks before considering a scoped implementation correction.

Two App processes (candidate and Latest) were observed after candidate launch. Both were preserved. User was told to identify candidate using commit 1188d59 and the Candidates path. No claim that the Latest process exercised the candidate fix is made.

## Publication decision

Formal release conditions: NOT MET. No new public version/tag, Appcast, Latest replacement or main merge was performed. This is a local ad hoc signed candidate; Developer ID/notarization remain outside this verification.

Next user action: in the candidate, verify About commit/path, open Settings credential management -> Guest sudo password -> Update password (the existing standalone sudo verification action), enter credentials only in secure fields, keep remember disabled and explicitly execute that verification. Report its result/error; do not click game launch until the identity/preflight and Guest configuration boundary have been assessed. Further testing can then resume on the actual authenticated candidate session.

## Concurrent Latest update and user screenshot

During validation an external/concurrent UI-simplification task replaced Latest. Its embedded source is now 918db0affdcf079ebfebd310b04223d3798dcb6f (still build 2026110402), executable SHA256 50d176122baf1d7fec1c06770151c69208f708b62c0704d18120a27968012f45. This task did not run the publisher or modify Latest. Both App processes were preserved. Candidate source/path/hash remain unchanged. Never treat the shared build number as proof of candidate identity.

User screenshot shows completed SSH diagnostics with Guest identity, but explicitly states no sudo execution. It does not show the About commit/path, so it is not accepted as candidate sudo success. Remember checkboxes were selected in the screenshot; user was instructed to uncheck them for this validation. No agent action persisted credentials, but the screenshot alone cannot establish that no earlier user action saved an SSH item. Do not delete existing Keychain items to make that claim.
