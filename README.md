<div align="center">
  <img src="docs/assets/app-icon.png" width="128" alt="HD2FXNative icon">
  <h1>HD2FXNative</h1>
  <p>HELLDIVERS 2 FX Launcher · Apple Silicon macOS</p>
</div>

[简体中文](README.zh-CN.md) | [English](README.md)

## English

HD2FXNative is an unofficial community launcher and management tool for Apple Silicon Macs. Built with SwiftUI and a native core, it helps users inspect FX, configure the runtime environment and manage game performance settings.

### Screenshots

These are real windows from different historical Debug builds, **not final v1.0.0 screenshots**. Final captures must be taken, reviewed and replaced after the final build; see [capture provenance](docs/images/README.md).

| Dashboard | First-Run Setup |
| --- | --- |
| ![Dashboard](docs/images/en/dashboard.png) | ![First-Run Setup](docs/images/en/first-run-setup.png) |
| Environment | FX Manager |
| ![Environment](docs/images/en/environment.png) | ![FX Manager](docs/images/en/fx-manager.png) |
| Game Performance | Settings |
| ![Game Performance](docs/images/en/performance.png) | ![Settings](docs/images/en/settings.png) |
| Logs | |
| ![Logs](docs/images/en/logs.png) | |

### Download and installation

**Release target: HD2FXNative v1.0.0.** GitHub has no published release. The inspected local App is version `0.1.0`, arm64 and ad hoc signed without a Developer ID. It has no verified Apple notarization. Gatekeeper may block a downloaded copy. The public DMG and its SHA-256 are pending. [GitHub Releases](https://github.com/LSJOP/helldivers2-fx-launcher/releases)

After publication, install on an Apple Silicon Mac running macOS 14 or later.

1. Download the macOS arm64 DMG from the published release.
2. Run `shasum -a 256 <downloaded-dmg>` and compare the result with the SHA-256 in the release notes. Open the DMG after they match.
3. Drag HD2FXNative to Applications.
4. Open HD2FXNative.
5. Select an installed FX Steam Launcher in FX Manager and follow First-Run Setup. You need SteamOS with Steam and HELLDIVERS 2 (AppID 553850) installed under an account that owns the game. The Guest must be reachable over SSH. Enter required credentials in the App and review the proposed changes.
6. Choose **Launch HELLDIVERS 2** on Dashboard.

For source builds, see the [development guide](docs/NATIVE_DEVELOPMENT.md).

### Features

- Dashboard starts the guarded HELLDIVERS 2 launch workflow. FX Manager inspects the selected FX installation and exposes supported FX/Steam actions.
- First-Run Setup checks Guest identity, runtime capabilities and component integrity. Approved configuration can install the pinned Proton-JE package, select a verified Steam compatibility tool and merge launch options while retaining custom arguments. Detection is read-only. Deployment and recovery require their own checks.
- Environment reports FEX and Proton-JE evidence. SSH and sudo credentials can be reused separately in process memory within the verified target/session.
- The Swift App provides seven native pages, logs, scoped performance controls and ten interface languages. Optional SteamOS installation steps require Python 3.
- Settings includes Sparkle update integration. Published update service and end-to-end installation have yet to be verified.

### Known Issues

- FX and SteamOS compatibility depends on the selected build and runtime evidence. The current launch path has a recorded proxy mismatch. Safe FX stop/restart remains unavailable.
- A real Guest built an experimental FEX candidate. Its executable hash failed deployment review. Candidate installation, recovery and game compatibility remain unverified. Alternate Proton-JE builds and fresh SteamOS deployment require validation.
- A historical Native build reached the game menu/ship on November 5. Final-package launch, single-player missions, EAC and multiplayer remain separately unverified.
- Public distribution, Gatekeeper handling and signed automatic updates are pending. The inspected local App uses ad hoc signing, without verified notarization.
- [Acceptance report](docs/acceptance/RELEASE_READINESS_REPORT.md) · [Known issues detail](docs/acceptance/KNOWN_ISSUES.md) · [First-run acceptance](docs/testing/NATIVE_FIRST_RUN_ACCEPTANCE.md) · [Update integration](docs/NATIVE_UPDATES.md) · [Performance limits](docs/GAME_PERFORMANCE.md)

### Changelog

Unreleased changes include Dashboard launch, first-run Proton-JE verification and Steam configuration, experimental FEX review and recovery, and SSH authentication fixes. See the [changelog](CHANGELOG.md) and [original launcher history](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script).

### Disclaimer

This community project is not affiliated with the makers of HELLDIVERS 2; names and marks belong to their respective owners. No project-wide source license has been selected. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party components and artwork.

### Documentation

User and developer guides, architecture notes and historical reports are available in the [documentation index](docs/README.md).

Development resumes from [current status](docs/DEVELOPMENT_STATUS.md) and [handoff](docs/NATIVE_APP_DEVELOPMENT_HANDOFF.md), with main source and AGENTS.md as authority. Unmerged candidates and live acceptance are tracked separately.
