# HELLDIVERS 2 FX Launcher — Native App

[English](README.md) | [简体中文](README.zh-CN.md)

An unofficial macOS tactical terminal built with **SwiftUI + AppKit**, reusing the original Python Core through a supervised JSONL Bridge. **Functional migration developer preview**, not an official product.

## Current status and features

This describes `feature/macos-native-app`; `main` may still contain the earlier read-only preview. See the [capability checklist](docs/FUNCTION_MIGRATION.md) for individual migration states.

- Five tactical pages, native navigation/refresh shortcuts and dark appearance by default.
- Real host metadata, bounded FX versions and discovered paths; explicit detailed runtime inspection.
- Native entrypoints for original launch, SSH/Guest/Steam checks, performance configuration, host network tests, network profile and recovery. These are wired to real Core functions; live acceptance remains pending.
- Configuration read/edit/save with validation, revision conflict checks, unknown-field preservation, backup and atomic replacement.
- Real progress/error streaming, bounded/redacted logs, search/filter/copy, user-reported match history and report export.
- Official stable/preview release query and bounded original help summary; no automatic installation.
- All ten original catalogs retained: zh-CN, en, ja, ko, ru, es, de, fr, pt-BR, zh-TW. Languages are selectable; new Native strings remain partly translated and fall back to English.

Refresh stays read-only. Writes, SSH and launch require explicit actions and consent. Specific Guest, performance and Wi-Fi changes require additional approval. Cancellation attempts supported recovery; already started processes may continue. Recheck actual state after interruption.

## Requirements

Apple Silicon, macOS 14+, complete Xcode with macOS SDK, Python 3.9+. Runtime operations also require an existing complete legacy launcher directory with the originally verified FX/gvproxy assets and compatible SSH configuration. The App does not install, relocate or silently select runtime assets.

No signed/notarized ready-to-install release is available. Runtime binaries, game files, fonts, credentials and Guest images are not bundled.

## Installation and use

```sh
git clone --branch feature/macos-native-app --recurse-submodules https://github.com/LSJOP/helldivers2-fx-launcher.git
cd helldivers2-fx-launcher/native-app
./script/build_and_run.sh --xcode-only
open build/Debug/HD2FXNative.app
```

Existing clones: run `git submodule update --init --recursive` at the repository root after selecting the branch. Source ZIPs omit submodules. The pinned archive supplies the metadata adapter, selected original Core sources and locale catalogs. Packaging does not run launch operations or download dependencies.

Settings selects language, appearance and an existing Python interpreter (default `/usr/bin/python3`). UI preferences and runtime-root selection are session-only. Open the relevant action panel, select the existing full legacy directory when requested and review changes before approving. Opening a page does not run a live operation.

Configuration: `~/Library/Application Support/Helldivers2FXLauncher/settings.json`. The editor shows target/revision and backs up before replacement. Native diagnostics/reports: `~/Library/Application Support/Helldivers2FXLauncher/native`. Original recovery receipts may also be written under the selected legacy directory. Secrets use stdin, never command arguments; original SSH settings control Keychain use. Verify authentication and target settings before connecting.

## Not implemented or not verified

- FX/Guest/SSH/Steam execution, EAC and multiplayer need fresh user-initiated runtime acceptance. Isolated checks/builds do not prove gameplay or matchmaking.
- Original binary/target guards remain enforced; arbitrary FX versions are not interchangeable.
- Full Native translations, complete help/changelog presentation and broader environment reports remain partial.
- The archived menu did not implement FX version switching or automatic update installation.
- CrossOver and signing/notarization remain future work. The Dashboard uses the user-supplied generated soldier illustration, bundled in the HelldiverHero asset catalog; a whole UI preview is not used as artwork.
- GitHub Actions remains unpublished because the current token lacks `workflow` permission; use local checks.

File presence, a running service, reachability, SSH authentication and game-service availability are separate evidence. Launch does not prove EAC/multiplayer; match submissions remain user reports.

## Branches and original script archive

- [main](https://github.com/LSJOP/helldivers2-fx-launcher/tree/main): Native mainline, potentially behind development.
- [feature/macos-native-app](https://github.com/LSJOP/helldivers2-fx-launcher/tree/feature/macos-native-app): active migration.
- [legacy-script](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script): preserved script history and pinned compatibility supplement; unchanged by this migration.

Terminal launcher: [archive README](https://github.com/LSJOP/helldivers2-fx-launcher/blob/legacy-script/README.md), [script ZIP](https://github.com/LSJOP/helldivers2-fx-launcher/archive/refs/heads/legacy-script.zip). Old main.zip links now download Native source; replace main with legacy-script in script-specific links. Original baseline: [0205aca](https://github.com/LSJOP/helldivers2-fx-launcher/tree/0205acaec3b32024df180a6dfb8ecc587e2f1914). No Release/Tag was removed.

## Development and license

Follow [AGENTS.md](AGENTS.md). Batch related changes; use `native-app/script/run_checks.sh` for affected Bridge/service/packaging behavior. Checks use temporary data and do not launch a real game. Maintain this README and [Chinese](README.zh-CN.md) together; documentation-only edits need link checks, no App builds.

No project-wide source license has been selected; do not assume blanket redistribution permission. HELLDIVERS 2 marks belong to their owners. Tactical geometry is drawn in code; no official artwork is bundled. See [rights/provenance](THIRD_PARTY_NOTICES.md) and archive notices.
