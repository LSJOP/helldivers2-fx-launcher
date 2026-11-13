# Deployment test results · 2026-11-04

Scope: isolated temporary filesystem, synthetic FX bundle, local PTY/closed-port transport fixtures and read-only host metadata. No Guest SSH session, VM creation, sudo configuration write, game/EAC/multiplayer launch or Latest change was performed.

## Automated verification

`native-app/script/run_checks.sh` is the reproducible entry point. Evidence is under ignored `native-app/evidence/`; no raw user/Guest logs are committed.

| Check | Cases | Scope |
| --- | ---: | --- |
| Deployment | 66 | Production engine on real isolated files; generated package install/recovery shell on fixture HOME, boot read and Linux utility adapters |
| Privileged executor | 30 | Per-invocation sudo authentication, no cache reliance, target guards |
| Network | 66 | Runtime Guest IPv6 transactions and bounded diagnostics, fixtures only |
| Native Core | 62 | Contracts, configuration, bounds, integrity, fail-closed behavior |
| Native integration | 22 | Real service dispatch; FX version discovery uses a synthetic bundle instead of installed FX |
| SSH | 35 | Controlled PTY, no echo, closed local port, remote sudo quoting/error classification |
| FX identity | 16 | Process ancestry and signature-bound failure paths |
| Launch / GUI state | 18 | Actual timing, terminal status, no inferred gameplay success |
| Memory-only credentials | 25 | Independent roles, rejection/scope/clear, no persistence API |
| Performance | 15 | Guarded editor state, verification vs actual runtime distinction |
| FX selection | 17 | Zero/one/multiple candidates, selection/revision safety |
| Localization negative fixtures | 8 | Missing/duplicate/format/placeholder/literal/orphan cases |
| Screenshot negative fixtures | 8 | Provenance/path/language/hash failures |
| Release history | 10 | Existing authenticated history protections |
| Update resources | 5 | Existing resource/bundle behavior |

Swift checks after main integration: 372. Python negative/regression fixtures: 31. Documentation gate: 15 checks. Ten languages have identical active-key coverage and no missing translations. Inspect final evidence/artifact metadata for the exact completed build/run. Human naturalness review of all ten languages is NOT_TESTED.

Deployment cases include absent/unapproved FEX/Proton, historical fingerprint insufficient for readiness, unsupported versions, unknown/mixed/corrupt files, exact consent, insufficient space, Steam/game active, SSH-like disconnection, boot/target/revision drift, cancellation before write, mid-write failure, pending-receipt recovery, restore failure, external updates, repeat detection, preserve custom launch options, conflicting/duplicate/quoted assignment rejection, duplicate/malformed VDF rejection, package installation, known-tree backup replacement, unknown-tree rejection, full inventory readback, interrupted directory swap and recovery, and conditional network consent. Actual generated package shell is executed against a fixture filesystem; mapping `/proc` and Linux utilities is expressly not a real Guest test.

## Build / UI

Independent Xcode Debug builds passed during development. Real standalone capture-copy windows launched through LaunchServices. zh-CN and en First-Run Setup, Dashboard and Settings captures were reviewed for language, visible clipping, empty secure fields and honest Unknown states. Manifest records real build 2026110411 and pixel hashes. These are actual unmodified App windows; plan/result/live authentication interaction screenshots remain NOT_TESTED. Historical unaffected screenshots are explicitly labelled.

Final artifact identity and source fingerprint are recorded by `native-app/script/record_first_run_build.py` after the final source commit and build. No Developer ID signing, notarization, updater installation or production release is asserted.

## Remaining boundaries

BLOCKED: reviewed FEX/Proton artifacts, distributable build/license provenance, installed full-manifest readiness and activation of package import/download UI.

NOT_TESTED: real Guest passworded SSH/sudo, real transport loss during mutation, real VM switching, actual FX/Guest graphics configuration, kernel IPv6 cascade behavior, clean-VM Native deployment/redeployment/recovery, Steam compatibility-tool runtime recognition, game menu/single-player, official EAC chain and multiplayer. Network route/process/file checks do not establish Steam/game endpoint reachability. Recovery currently rejects a different bound process/boot identity; no automatic cross-boot rebind is claimed.
