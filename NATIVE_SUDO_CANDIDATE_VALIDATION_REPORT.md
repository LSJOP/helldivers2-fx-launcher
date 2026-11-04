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
| Full Guest identity, current live master | PASS | After user App authentication, exact FX/gvproxy/SSH peer and Guest boot/marker checks passed; initial absent-master attempt remains recorded |
| App secure password entry/authentication | PASS (user screenshot); candidate attribution pending About confirmation | Details show password_verified=true, sudo=authenticated, configuration_changed=false |
| Sudo reuse across separate SSH commands | FAIL | Two independent sudo -n -v probes require a password; exact production sudoCommandArgs with harmless id -u also fails status 1 requiring a password |
| Credential status UI | PASS for authentication detail; storage restricted | Screenshot shows authenticated; Keychain access restriction is separate from sudo authentication, no saved-password success inferred |
| CheckingCompatibility complete | NOT TESTED; prerequisite read-only checks PASS | Hash checks, host proxy and launch options pass. IPv6 flags are all 0, so full stage would write Guest networking settings; not authorized/executed |
| Game launch | NOT TESTED | Existing game count 0; Steam service reported stopped. No start requested beyond the configuration boundary |
| Game menu/playability/EAC/multiplayer | NOT TESTED | No inference from Steam or game processes |

The initial live harness stopped at an absent/unverified SSH master. After user App authentication, the same harness passed full identity and all read-only compatibility probes. It ran authorization-only sudo probes without password input; it did not execute IPv6 writes, Steam start or game launch. Raw Guest boot identifiers are not copied into this report.

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

## Final live findings

A second user screenshot shows password_verified=true, sudo=authenticated, configuration_changed=false and the Guest sudo authenticated event. It establishes actual App password verification success, distinct from the prior terminal-only success. The screenshot still lacks About commit/path; exact candidate UI attribution awaits user confirmation. Both candidate and a concurrently updated Latest App remained open.

Immediately afterward, full identity verification over the current master passed. Compatibility hashes, local proxy and launch options passed. Read-only values: IPv6 disable flags all/default/eth0/lo = 0/0/0/0; Steam service stopped; game process count 0. A Steam login log observation was true but does not establish a currently running Steam session.

Two separate SSH sudo -n -v checks returned AUTH_REQUIRED. A further check using the exact production sudoCommandArgs with harmless id -u input returned status 1 and a-password-is-required, with no root execution observed. Thus sudo validation in one session does not provide usable authorization for the subsequent independent invocation in this environment. The current evidence does not identify the precise sudo timestamp policy, so none is asserted. The candidate fails this integration requirement despite the quoting fix succeeding. Do not classify this as an incorrect password.

Four IPv6 original values are now recorded as 0. The proposed compatibility transaction would set all four to 1 for this Guest boot, disabling IPv6. No such write was performed. A future explicitly authorized test would need same-boot identity checks and restoration of precisely these four original 0 values; no sudoers, persistent sysctl file or user password changes are justified.

Formal publication conditions remain NOT MET. The next implementation step is to make the privileged transaction authenticate within its own controlled SSH execution, without relying on cross-session sudo timestamps, while keeping secrets out of command arguments/environment/logs and preserving the Guest boot/consent guards. This task built and evaluated exactly 1188d59; it did not silently replace that candidate with another implementation. Revalidate a follow-up candidate before any game or release acceptance.
