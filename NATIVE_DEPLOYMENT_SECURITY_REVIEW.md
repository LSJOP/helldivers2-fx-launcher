# Deployment security review

IMPLEMENTED: process-memory independent SSH/sudo credentials, no Native Keychain API; secure UI fields; controlled PTY/stdin; no credential argv/env/temp files/preferences/logs. Existing archived Python credential code is unchanged and not bundled/executed as the Native backend. Old Keychain records are not touched. Memory clearing is logical lifetime clearing, not a claim of cryptographic zeroization of Swift String copies.

IMPLEMENTED: profile-derived plans only; fresh target/config revision/value comparison; full-file VDF compare-and-swap; Guest boot/process/path checks; app/Guest locks; private durable receipts before writes; per-step verification; no retry/reconnect of failed mutations; drift-aware reverse recovery; explicit authorization for setup and selected recovery. Receipts contain configuration values, not auth secrets. Launch strings classified as sensitive are rejected. App secret redaction remains active.

IMPLEMENTED: approved-source hash + full manifest importer, all inventory entries required, extra/mixed files rejected, strict paths, tar checksum/type/permissions validation. Existing unknown FEX trees are not overwritten; Proton installs into a version-specific path, retains other versions, and never recreates a Prefix. No EAC files or anti-cheat settings are modified. Component backup/recovery retains unique directories; failure leaves a RecoveryRequired receipt.

IMPLEMENTED: initial network policy preserves state. No Host global IPv6 or proxy software installation. Guest-only optional primitive covers all IPv6 interfaces because conf/all cascades; exact profile/consent/interface-set requirements precede its use. A single sudo invocation receives the secret through stdin. CheckingCompatibility performs no network writes.

BLOCKED: reviewed FEX/Proton release packages, actual distribution license/build evidence, package-specific symlink/PAX handling, full installed-tree manifest readiness, public download activation. The memory-only parallel checkout was not treated as a verified dependency.

NOT_TESTED: real Guest passworded sudo/SSH disconnect behavior, VM switching races, real package transfer/install/recovery, live FX preferences, rendering, game/EAC/multiplayer and fresh VM installation. Advisory locks cannot stop externally launched Steam or all third-party file writers. Power-loss/stale Guest lock recovery needs operator review; unknown state is never reported as installed/healthy. Host route/process evidence is not endpoint/UDP/multiplayer evidence.
