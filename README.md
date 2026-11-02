# HELLDIVERS 2 FX Launcher — Native App

[English](README.md) | [简体中文](README.zh-CN.md)

A macOS tactical terminal for HELLDIVERS 2 FX Launcher, built with **SwiftUI + narrowly scoped AppKit integration**. **Native Phase 1: read-only developer preview.** This is an unofficial project; no official endorsement is claimed.

## Current status and implemented features

| Area | Available now |
| --- | --- |
| Navigation | Native Sidebar, Dashboard, Environment, FX Manager, Logs and Settings; Cmd+1…5 navigation and Cmd+R refresh |
| Interface | Chinese/English functional labels; dark by default, optional light/system appearance; session-only preferences |
| Host inspection | Real macOS, architecture and Python metadata through a supervised Python JSONL bridge |
| Dependency inspection | Local file presence and bounded FX version/structure metadata; discovery does not establish runtime readiness |
| Logs | App and read-only Bridge logs from the current session; historical game logs are unavailable |
| Development branch additions | `feature/macos-native-app` adds a unified five-page tactical layout and log search, severity filtering and copy. Entries without severity metadata remain unclassified. These additions are not yet merged into main. |

Game launch is **disabled**, with an explicit reason. FX runtime, Guest, SSH, EAC and multiplayer remain **unverified**. Phase 1 does not install/update software, start games or write launcher settings.

## Requirements

- Apple Silicon Mac running macOS 14 or newer.
- Complete Xcode with a macOS SDK for local builds.
- An existing Python 3.9 or newer interpreter.

A ready-to-install, signed/notarized Native release is **not available**. No runtime binaries, game files, fonts, credentials or Guest images are bundled.

## Installation and use

Build main locally:

```sh
git clone --recurse-submodules https://github.com/LSJOP/helldivers2-fx-launcher.git
cd helldivers2-fx-launcher/native-app
./script/build_and_run.sh --xcode-only
open build/Debug/HD2FXNative.app
```

To use the development additions, clone that branch instead:

```sh
git clone --branch feature/macos-native-app --recurse-submodules https://github.com/LSJOP/helldivers2-fx-launcher.git
```

For an existing clone, run `git submodule update --init --recursive` at the repository root after checking out the intended branch. The `CoreSnapshot` submodule is pinned to an archive commit; a remote branch update does not silently change build input. The build copies only seven allowlisted compatibility modules plus VERSION into the App. It does not execute legacy launch scripts or download/install dependencies.

Use Settings to choose Chinese/English and dark/light/system appearance. Choices apply only to the current App session. The default interpreter is `/usr/bin/python3`; if unavailable, select an existing suitable interpreter and refresh. Finding a dependency file or FX candidate does not prove a working game environment.

The Native source ZIP does **not** include submodule contents. Use the recursive clone instructions above.

## Not implemented or not verified

- Native game launch, runtime/version switching and automatic installation/updates are unavailable.
- CrossOver integration and restoration of all ten legacy interface languages remain future work; Native currently provides Chinese and English.
- FX runtime, Guest, SSH, Steam, EAC and multiplayer/gameplay validation are not established by host metadata, file presence or bundle structure.
- The development branch reserves a Dashboard soldier-art container, but a separately licensed standalone asset has not been integrated. A whole UI preview is not used as background artwork.
- Distribution signing/notarization and a ready-to-install Native release remain future work.
- GitHub Actions is not enabled: the current OAuth token lacks the `workflow` permission needed to publish its configuration. Use the documented local checks.

## Branches and original script archive

- [`main`](https://github.com/LSJOP/helldivers2-fx-launcher/tree/main): Native App mainline.
- [`feature/macos-native-app`](https://github.com/LSJOP/helldivers2-fx-launcher/tree/feature/macos-native-app): daily Native development.
- [`legacy-script`](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script): complete original FX Launcher scripts and history, plus the read-only Native compatibility snapshot.

Use the [archived script README](https://github.com/LSJOP/helldivers2-fx-launcher/blob/legacy-script/README.md) and [script ZIP](https://github.com/LSJOP/helldivers2-fx-launcher/archive/refs/heads/legacy-script.zip) for the terminal launcher. Existing script installations are not modified. Old `main.zip` links now download Native source; old raw/main script paths no longer resolve. Replace `main` with `legacy-script` for script-specific links. The pre-migration commit remains [0205aca](https://github.com/LSJOP/helldivers2-fx-launcher/tree/0205acaec3b32024df180a6dfb8ecc587e2f1914). No existing Release or Tag was removed.

## Development and documentation

Follow [AGENTS.md](AGENTS.md) for batched development and minimal necessary verification. Run `native-app/script/run_checks.sh` when Bridge, packaging or service behavior changes. README-only updates require document/link checks, not App builds or launches. Maintain this README and [the Chinese version](README.zh-CN.md) together, with matching feature, version, installation and development-status information.

## License and rights

A project-wide source license has **not been selected**. Do not assume the entire repository is licensed for redistribution. HELLDIVERS 2 and related marks belong to their respective owners. The tactical geometry is drawn in code; no official game artwork is bundled. See [rights and provenance](THIRD_PARTY_NOTICES.md) and the historical notices in `legacy-script` for the actual scope and unresolved licensing questions.
