<div align="center">
  <img src="docs/assets/app-icon.png" width="128" alt="HD2 FX Launcher icon">
  <h1>HD2 FX Launcher</h1>
  <p>HELLDIVERS 2 FX Launcher · Apple Silicon macOS</p>
</div>

[简体中文](README.zh-CN.md) | [English](README.md)

### [🟨 ⬇️ Download HD2 FX Launcher — Latest Stable](https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/v1.0.0/HD2FXNative-v1.0.0-macOS-arm64.dmg)

**🟨 Stable Release · v1.0.0** · **macOS · Apple Silicon / arm64**

**[⬇️ Download DMG](https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/v1.0.0/HD2FXNative-v1.0.0-macOS-arm64.dmg)** · [All Releases](https://github.com/LSJOP/helldivers2-fx-launcher/releases)

## English

HD2 FX Launcher is an unofficial community launcher and management tool for Apple Silicon Macs. Built with SwiftUI and a native core, it helps users inspect FX, configure the runtime environment and manage game performance settings.

FX 1.9.9 test-Guest repair now reaches the game through the GUI with the historically verified RF FEX components. Main menu/ship was confirmed by the user; single-player, multiplayer and end-to-end updating remain untested. Production FX 1.9.12 was inspected offline without writes. See [repair evidence](docs/environment/FX199_RF_REPAIR_20261114.md).

### Screenshots

These real bilingual windows were captured from the integrated Debug source on 2026-11-14 and visually reviewed. They show development changes under Unreleased, **not the published v1.0.0 DMG**; see [capture provenance](docs/images/README.md).

The Dashboard retains five cards: FX, virtual machine, Steam, EAC and multiplayer. Green identifies an observed FX/Steam process or a verified Guest SSH connection; yellow means an active check, red an explicit stage failure, and gray missing or stale evidence. Process detection, completed checks and menu/single-player confirmation do not establish EAC loading or multiplayer success. The isolated status matrix validates display logic; it does not establish live game readiness.

| Dashboard | First-Run Setup |
| --- | --- |
| ![Dashboard](docs/images/en/dashboard.png) | ![First-Run Setup](docs/images/en/first-run-setup.png) |
| Environment | FX Manager |
| ![Environment](docs/images/en/environment.png) | ![FX Manager](docs/images/en/fx-manager.png) |
| Game Performance | Settings |
| ![Game Performance](docs/images/en/performance.png) | ![Settings](docs/images/en/settings.png) |
| Logs | |
| ![Logs](docs/images/en/logs.png) | |

### Features

- Dashboard starts the guarded HELLDIVERS 2 launch workflow. FX Manager inspects the selected FX installation and exposes supported FX/Steam actions.
- First-Run Setup checks Guest identity, runtime capabilities and component integrity. Approved configuration can install the pinned Proton-JE package, select a verified Steam compatibility tool and merge launch options while retaining custom arguments. Detection is read-only. Deployment and recovery require their own checks.
- Environment reports FEX and Proton-JE evidence. SSH and sudo credentials can be stored separately in encrypted local storage for a verified target; reuse after restart still requires real-world acceptance.
- The Swift App provides seven native pages, logs, scoped performance controls and ten interface languages. Optional SteamOS installation steps require Python 3.
- Settings includes Sparkle update integration. Published update service and end-to-end installation have yet to be verified.

### Installation

Current App: `1.0.0` (build `2026111403`), macOS 14+ Apple Silicon arm64. Ad-hoc signed; no Apple Developer ID signature or Apple notarization. Gatekeeper may block the download. Verify the [SHA-256 file](https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/v1.0.0/HD2FXNative-v1.0.0-macOS-arm64.dmg.sha256) before opening. If blocked, use Privacy & Security → Open Anyway for the verified App.

1. Download the macOS arm64 DMG from the published release.
2. Run `shasum -a 256 <downloaded-dmg>` and compare the result with the SHA-256 in the release notes. Open the DMG after they match.
3. Drag the App to Applications.
4. Open the App.
5. Select an installed FX Steam Launcher in FX Manager and follow First-Run Setup. You need SteamOS with Steam and HELLDIVERS 2 (AppID 553850) installed under an account that owns the game. The Guest must be reachable over SSH. Enter required credentials in the App and review the proposed changes.
6. Choose **Launch HELLDIVERS 2** on Dashboard.

For source builds, see the [development guide](docs/NATIVE_DEVELOPMENT.md).

### Known Issues

Release scope: shared launch/retry fixes and local encrypted SSH/sudo storage are included in this artifact. FX 1.9.9 test GUI launch and user-confirmed menu/ship are recorded. Single-player, EAC/multiplayer, fresh deployments and full Sparkle installation/rollback remain unverified. The bundled public updater is disabled/unconfigured; use the Release DMG for manual installation. Production FX 1.9.12 was only inspected offline.


- FX and SteamOS compatibility depends on the selected build and runtime evidence. The current launch path has a recorded proxy mismatch. Safe FX stop/restart remains unavailable.
- A real Guest built an experimental FEX candidate. Its executable hash failed deployment review. Candidate installation, recovery and game compatibility remain unverified. Alternate Proton-JE builds and fresh SteamOS deployment require validation.
- A historical Native build reached the game menu/ship on November 5. Final-package launch, single-player missions, EAC and multiplayer remain separately unverified.
- Gatekeeper handling and signed automatic updates remain pending. The inspected local App uses ad hoc signing, without verified notarization.
- [Acceptance report](docs/acceptance/RELEASE_READINESS_REPORT.md) · [Known issues detail](docs/acceptance/KNOWN_ISSUES.md) · [First-run acceptance](docs/testing/NATIVE_FIRST_RUN_ACCEPTANCE.md) · [Update integration](docs/NATIVE_UPDATES.md) · [Performance limits](docs/GAME_PERFORMANCE.md)

### Changelog

[v1.0.0 — 2026-11-14](https://github.com/LSJOP/helldivers2-fx-launcher/releases/tag/v1.0.0) · Stable release, build `2026111403`. See [release notes](CHANGELOG.md).

Unreleased changes include Dashboard launch, first-run Proton-JE verification and Steam configuration, experimental FEX review and recovery, and SSH authentication fixes. See the [changelog](CHANGELOG.md) and [original launcher history](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script).

### Disclaimer

This community project is not affiliated with the makers of HELLDIVERS 2; names and marks belong to their respective owners. No project-wide source license has been selected. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party components and artwork.

### Documentation

User and developer guides, architecture notes and historical reports are available in the [documentation index](docs/README.md).

Development resumes from [current status](docs/DEVELOPMENT_STATUS.md) and [handoff](docs/NATIVE_APP_DEVELOPMENT_HANDOFF.md), with main source and AGENTS.md as authority. Unmerged candidates and live acceptance are tracked separately.
