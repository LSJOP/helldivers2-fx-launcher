<div align="center">
  <img src="docs/assets/app-icon.png" width="128" alt="HELLDIVERS 2 FX Launcher icon">
  <h1>HELLDIVERS 2 FX Launcher</h1>
  <p>A HELLDIVERS 2 FX launcher and management tool for Apple Silicon Macs.</p>
</div>

<a id="english"></a>
<a id="简体中文"></a>

[**English**](README.md) | [**简体中文**](README.zh-CN.md)

![macOS](https://img.shields.io/badge/macOS-14%2B-0078D4?style=flat-square&labelColor=171A1F)
![Apple Silicon](https://img.shields.io/badge/Platform-Apple%20Silicon-0078D4?style=flat-square&labelColor=171A1F)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0078D4?style=flat-square&labelColor=171A1F)
![Status](https://img.shields.io/badge/Status-Development%20Preview-F29D38?style=flat-square&labelColor=171A1F)
![Version](https://img.shields.io/badge/Native-0.1.0-FFD600?style=flat-square&labelColor=171A1F)

[Screenshots](#en-screenshots) · [Features](#en-features) · [Installation](#en-installation) · [Quick start](#en-usage) · [Compatibility](#en-development) · [Changelog](#en-changelog) · [Legacy script](#en-legacy)

<a id="en-overview"></a>

A native **SwiftUI + AppKit** interface over the original Python Core: launch the game, inspect the selected FX environment and read performance settings from six focused pages. The interface defaults to dark, with inline operation feedback and advanced details available when needed.

> [!IMPORTANT]
> **Development preview.** No official installer has been released. The completed Native snapshot is integrated into [main](https://github.com/LSJOP/helldivers2-fx-launcher/tree/main); [feature/macos-native-app](https://github.com/LSJOP/helldivers2-fx-launcher/tree/feature/macos-native-app) is retained for development history. Runtime binaries, game files and Guest images are not included.

<a id="en-screenshots"></a>

## Screenshots

[![Dashboard](docs/images/en/dashboard.png)](docs/images/en/dashboard.png)

| Environment | FX Manager |
| --- | --- |
| [![Environment](docs/images/en/environment.png)](docs/images/en/environment.png) | [![FX Manager](docs/images/en/fx-manager.png)](docs/images/en/fx-manager.png) |

<details>
<summary>Game Performance</summary>

[![Game Performance](docs/images/en/performance.png)](docs/images/en/performance.png)

[![Performance actions](docs/images/en/performance-actions.png)](docs/images/en/performance-actions.png)

</details>
<details>
<summary>Logs, Settings and Software Update</summary>

[![Logs](docs/images/en/logs.png)](docs/images/en/logs.png)
[![Settings](docs/images/en/settings.png)](docs/images/en/settings.png)
[![Software Update](docs/images/en/settings-updates.png)](docs/images/en/settings-updates.png)

</details>


Eight English screenshots captured from the current real Native Debug App (0.1.0, build 1) on 2026-11-03, with read-only host metadata. Pixels are unmodified; no UI/status was composited. Scrolled views show performance actions and software update. Capture copies isolate App preferences and disable credential autoload; no FX/Guest action or configuration write was performed. Supplied artwork is rendered inside the real App. Screenshots do not prove gameplay, performance gains or installation readiness. [Capture provenance and limitations](docs/images/README.md).

<a id="en-features"></a>

## Features

| Status | Capability |
| --- | --- |
| 🟢 Implemented | Six-page native interface, Cmd+1…6 navigation, dark/light/system appearance, bundled official project icon |
| 🟢 Implemented | Bounded host/FX discovery; validated configuration editing with revision checks, backup and atomic replacement |
| 🟢 Implemented | Searchable, filtered, bounded and redacted logs; diagnostic reports |
| 🟢 Implemented · Guarded writes | Hardware/current FX preferences and reference differences; scoped performance editing/backup/restore for the pinned FX 1.9.4 build |
| 🟠 In development | One-click environment inspection and background SSH operations; original-entry FX/Steam starts, independent SSH/sudo credential reuse; fresh live acceptance remains pending |
| 🟢 Implemented · Static coverage checked | Ten original Python catalogs retained separately; unified Native resources cover all ten languages. Missing Native text is shown as an explicit missing key, without English fallback. Translation naturalness still needs human review |
| ⚪ Planned / unavailable | Safe FX stop/restart, verified performance recommendations, signed/notarized installer |

Performance rules are local and reproducible. The recorded **M4 Pro / 24 GiB** settings are a candidate baseline, not comprehensive performance validation. Other hardware has no inferred writable profile. FX 1.9.4 with the pinned build supports a conservative CPU/memory/Vulkan/Metal HUD editor with preview, consent, verified backups and conflict-guarded restore. FX must be stopped; saved preferences need a fresh FX/Guest start and remain unverified. The original launch path overrides values and may reject custom settings: restore before using it. Super resolution and the 6144 MiB GPU budget remain read-only. Current localized screenshots include the new performance and update surfaces. [Parameter sources and limits](docs/GAME_PERFORMANCE.md).

<a id="en-requirements"></a>
<a id="en-installation"></a>

## Download and installation

**An official installer has not been released.** The repository [Releases page](https://github.com/LSJOP/helldivers2-fx-launcher/releases) currently has no published release; this is not a download button for a nonexistent package.

Source preview requirements: **Apple Silicon, macOS 14+, a complete Xcode/macOS SDK and Python 3.9+**. Game operations also require the existing complete legacy launcher directory, the original validated FX/gvproxy assets and compatible Guest access.

```sh
git clone --branch main --recurse-submodules https://github.com/LSJOP/helldivers2-fx-launcher.git
cd helldivers2-fx-launcher/native-app
./script/build_and_run.sh --xcode-only
open build/Debug/HD2FXNative.app
```

Existing clones need the intended branch and `git submodule update --init --recursive`. Source ZIPs omit the pinned Core submodule. See the [development guide](docs/NATIVE_DEVELOPMENT.md).

<a id="en-usage"></a>

## Quick start

1. Open the App; choose your language, appearance and existing Python interpreter in Settings.
2. Select the existing launcher directory on first use. Use **Inspect environment** for read-only Guest checks; FX must already be running. Use **Start FX** in FX Manager if needed.
3. Click **Launch HELLDIVERS 2** on Dashboard. The existing launch workflow performs its required checks automatically. Review start consent and any exact configuration-change preview; enter credentials only in App secure fields.
4. Use Game Performance for hardware and baseline comparisons, and Logs for failure details. A detected process does not establish arrival at the game menu.

<a id="en-development"></a>

## Compatibility status

| Evidence | Current result |
| --- | --- |
| Native App | Debug build and six-page smoke passed; current focused checks: 35 migration + 9 inference cases |
| FX / game process | Observed during the earlier recorded dedicated FX 1.9.4 launch; not a claim about every FX installation |
| Main menu / controllable ship | Explicitly confirmed by the user on 2026-11-03 in that recorded environment |
| Current GUI SSH / Guest read | Real backends wired; latest host check rejected a different running FX copy before connecting. Fresh success through the new actions remains pending |
| Single-player mission / independent EAC / multiplayer | **Unverified**, separately |
| Performance | Guarded saved-preference editing with backup/restore; no measured performance guarantee or automatic tuning |

> [!WARNING]
> Installation found ≠ runtime ready ≠ game process started ≠ main menu reached ≠ EAC accepted ≠ multiplayer working. No anti-cheat bypass is provided.

<a id="en-changelog"></a>

## Changelog

No official release has been published yet; the current Native version `0.1.0` is a development preview. Recent unreleased changes:

- Native six-page interface, bounded FX discovery, validated configuration editing, redacted logs and read-only performance comparison.
- GUI-driven FX/SSH actions and optional SSH/sudo credential remembering.
- Sparkle 2 update integration (feed/signing service not configured).

See the full history in [CHANGELOG.md](CHANGELOG.md).

## FAQ

- **Why are stop/restart or some Apply actions disabled?** Graceful exit is unverified. Performance editing requires the pinned FX 1.9.4 build, valid preferences, stopped FX and explicit preview/consent. Invalid backups or external changes block restore. The App does not force-stop FX.
- **Must I retype passwords?** Session reuse is the default. Optional remembering stores independently verified SSH/sudo credentials in a new App-owned macOS Keychain namespace; automatic reads suppress authorization dialogs. Locked/access-restricted storage falls back to secure input. Explicit access or App identity/signature changes may still require system authorization. Old script items are untouched.
- **Are automatic updates ready?** Manual GitHub Native-release checks work in Settings → Software Update. Stable is the default; Preview and automatic checks remain closed until verified service setup. A verified-download backend requires a trusted Ed25519 key and signed manifest; installation remains disabled without the signed Appcast, Developer ID and notarization/distribution conditions. Manual checks never install automatically. The automatic-check toggle stays disabled until the signed service is ready. Download verification includes signature, size and SHA-256; installation stays with official Sparkle. No production update package is published yet. Failures leave the current App intact; no installed/relaunched success is inferred. Release preparation verifies signed feed history before reusing it. [Setup and release gates](docs/NATIVE_UPDATES.md).

<a id="en-legacy"></a>

## Development and legacy script

- [main](https://github.com/LSJOP/helldivers2-fx-launcher/tree/main): integrated Native mainline.
- [feature/macos-native-app](https://github.com/LSJOP/helldivers2-fx-launcher/tree/feature/macos-native-app): retained Native development history; synchronize with main before reuse.
- [legacy-script](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script): original script archive; its history is preserved.
- [Development guide](docs/NATIVE_DEVELOPMENT.md) · [Migration evidence](docs/FUNCTION_MIGRATION.md) · [Performance](docs/GAME_PERFORMANCE.md) · [Updates](docs/NATIVE_UPDATES.md) · [Development rules](AGENTS.md)

<a id="en-disclaimer"></a>
<a id="en-license"></a>

## Disclaimer and license

Unofficial project; no endorsement or compatibility guarantee. HELLDIVERS 2 and related marks belong to their respective owners. A project-wide source license has **not been selected**; do not assume redistribution rights. See [rights and provenance](THIRD_PARTY_NOTICES.md), including the separate Sparkle license and supplied artwork notes.

Development checks: `python3 native-app/script/check_localization.py` reports ten-language key/format coverage and README review candidates; `native-app/script/run_checks.sh` and the pre-commit hook include this gate. UI changes require a review of both READMEs and their real screenshots. Both English and Simplified Chinese screenshots are refreshed for the integrated UI. Translation naturalness still needs human review. The release-check Actions template remains inactive; no CI workflow is configured.

FX selection V2 + automatic selection V2.1: the FX page, overview and launch panel share one persisted default. One identity/path-verified FX is selected automatically from the scan results; multiple installations preserve an existing valid choice or require selection. Missing/moved/updated defaults are revalidated. Selection remains **launch capability unverified** and never starts the game. Every game launch rescans the default and retains the original executable hash, identity, configuration and preflight guards. Other builds may be selected but can be blocked by those compatibility checks. FX application selection is separate from the helper/gvproxy resource directory: resolve it from the selected app’s bounded ancestors or the existing resource directory when possible, otherwise explicitly locate **launch resources** once. Repeated FX-directory selection is not required. Refresh and automatic inspection do not start FX, SSH or the game. Stop/restart remain unavailable. Parameter-scoped performance editing and backup restore require a stopped, pinned FX 1.9.4 and explicit preview/confirmation; inferred recommendations remain read-only.
