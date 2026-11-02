# HELLDIVERS 2 FX Launcher — Native App

A macOS tactical terminal for HELLDIVERS 2 FX Launcher, built with SwiftUI and narrowly scoped AppKit integration. **Native Phase 1: read-only developer preview.** This repository is not an official game product.

## Current capabilities

- Tactical Sidebar and Dashboard; dark by default, optional light/system appearance.
- Chinese/English interface with single-language functional labels and native navigation shortcuts (Cmd+1…5, Cmd+R).
- Real host metadata, bounded FX version metadata, dependency file presence and session logs through a supervised Python JSONL bridge.
- Game launch remains disabled with an explicit reason. FX runtime, Guest, SSH, EAC and multiplayer remain unverified. No installation, update, game launch or settings writes are performed by Phase 1.

## Requirements and installation

Apple Silicon Mac, macOS 14+, complete Xcode with a macOS SDK, and an existing Python 3.9+ interpreter. No ready-to-install, signed/notarized Native release is published. Build locally:

```sh
git clone --recurse-submodules https://github.com/LSJOP/helldivers2-fx-launcher.git
cd helldivers2-fx-launcher/native-app
./script/build_and_run.sh --xcode-only
open build/Debug/HD2FXNative.app
```

For an existing clone, first run `git submodule update --init --recursive` at the repository root. The CoreSnapshot submodule is pinned to the archive commit; updating its remote branch does not silently change the build input. The build copies only the seven allowlisted compatibility modules plus VERSION into the app. It never executes legacy launch scripts. No dependencies are downloaded or installed by the build script.

Settings choices are session-only. The default interpreter is `/usr/bin/python3`; select an existing suitable interpreter if unavailable. Finding a dependency or FX candidate does not prove a working game environment.

## Repository workflow

- [`main`](https://github.com/LSJOP/helldivers2-fx-launcher/tree/main): Native App mainline.
- [`feature/macos-native-app`](https://github.com/LSJOP/helldivers2-fx-launcher/tree/feature/macos-native-app): daily Native development.
- [`legacy-script`](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script): complete original FX Launcher scripts and history, plus the pinned read-only Native compatibility snapshot.

Follow [AGENTS.md](AGENTS.md) for batched changes and minimal necessary verification. Run `native-app/script/run_checks.sh` when Bridge/packaging/service behavior changes; static text or style edits do not require repeated full sweeps. GitHub Actions is not enabled yet: the current OAuth token lacks the workflow permission required to publish a workflow file. Use the documented local checks; no gameplay success or published binary is implied.

## Original script downloads

Use the [archived script README](https://github.com/LSJOP/helldivers2-fx-launcher/blob/legacy-script/README.md) and [script ZIP](https://github.com/LSJOP/helldivers2-fx-launcher/archive/refs/heads/legacy-script.zip). Old `main.zip` links now download Native App source, and old raw/main script paths no longer resolve. Replace `main` with `legacy-script` for script-specific links. The original pre-migration commit remains [0205aca](https://github.com/LSJOP/helldivers2-fx-launcher/tree/0205acaec3b32024df180a6dfb8ecc587e2f1914). No existing Release or Tag was removed.

The script archive ZIP includes its compatibility snapshot. The Native source ZIP does **not** include submodule contents; use the recursive clone instructions above. Existing script installations are not modified by this migration.

See [rights and provenance](THIRD_PARTY_NOTICES.md). Core launch integration, restored ten-language coverage, CrossOver support, distribution signing/notarization and runtime/gameplay validation are future work.
