[简体中文](CHANGELOG.zh-CN.md) | English

# Changelog

All notable changes to the HELLDIVERS 2 FX Launcher Native App are recorded here, newest first. Unreleased entries have no release date. This file is the single source of truth for user-facing release notes; the README summary, GitHub Release notes and the future Sparkle appcast reuse this reviewed text. Do not paste raw, unreviewed Git commit messages into it.

No official release has been published yet. The current Native App version `0.1.0` (build `1`) is a development preview, not a downloadable package.

## Unreleased

### Changed

- Replace the tall global FX info block with a compact FX status bar (name, version, detected/running state, Manage FX) and move path, gvproxy, SHA-256 and preflight diagnostics into FX Manager → Details & resource verification. Remove the duplicated FX version/path/status from the Dashboard runtime card and reorder the page around the hero and launch actions.


### Fixed

- Repair `PROTOCOL_ERROR · get_logs`: the native core now reports the `native_core_session` log source that the UI validates, and environment detection runs per method so one failed probe no longer blanks macOS/architecture/native-runtime and every other panel.
- Restore the App icon and asset catalog in Debug and Release: the resource-copy build phase no longer deletes the compiled `AppIcon.icns`/`Assets.car` and now also restores the ten `.lproj` bundles.
- Game launch no longer fails immediately with "FX not running": the launch path now auto-starts the verified FX once, waits for Guest, waits for Steam login, then sends the game request, with cancellation and stage reporting. Connection-only actions still require an already-running FX.
- Remove legacy Python Bridge wording (Bridge status, latest Bridge error, "Python executed the Bridge", "requires Python 3.9", Node runtime requirement) from the ten-language resources and the Logs source label.

### Added

- Release resource-integrity gate (`native-app/script/check_release_bundle.sh`): icon, asset catalog, ten languages, bundled gvproxy SHA-256, Sparkle, bundle identifier, version, architecture, no Python/Bridge, and code-signature verification.
- SwiftUI ↔ Native Core integration checks covering the log source contract, system info, environment, dependencies, FX discovery, catalog, configuration and fail-closed launch without a selection.


### Changed

- Replace the Python Bridge with a **Swift Native Core**. FX discovery, launch-resource integrity, launcher settings, scoped CPU/memory/Vulkan preferences, diagnostics, logging and the FX/Guest/Steam/game launch path are implemented in Swift. The original script directory and Node.js are no longer required at runtime.

### Removed

- Remove the bundled Python bridge, `legacy_operations.py`, `core_adapter.py` and the Python packaging build phase. No Python interpreter is invoked by the app, build or runtime.

### Fixed

- Reject symlinked or tampered bundled launch resources (gvproxy) with pinned SHA-256, and report a missing/hash-mismatched resource explicitly instead of launching.
- Persist launcher settings with revision guarding, a private backup and atomic replacement; restore requires confirmation and keeps a pre-restore copy.

### Known issues

- Live FX start, Guest authentication, Steam start, game launch, main-menu, EAC and multiplayer were **not** verified in this change. Their automated checks and host preflight do not prove gameplay.
- Rewriting real FX preferences requires a stopped FX; live apply/restore was not executed while FX was running.
- Distribution remains blocked: the Release app is ad-hoc signed and not notarized (no Developer ID / EdDSA publishing configuration). Code integration is not an end-to-end upgrade acceptance.


### Fixed

- Share launch-resource validation between inspection and execution, with exact paths and expected/actual SHA-256. Freeze the selected FX path throughout launch. Accept intact bundles signed by the verified FX publisher while retaining all original profile/process/Guest guards. FX 1.9.4/1.9.8 path and integrity checks do not establish gameplay compatibility.

### Added

- Integrate FX selection V2 and automatic selection V2.1: one shared, persisted default for FX management, overview and launch. Auto-select a sole identity/path-verified candidate; preserve valid manual choices; revalidate missing, moved and updated installations.
- Pass the selected FX path to the guarded existing backend. Resolve helper/gvproxy resources separately and avoid repeated FX pickers. Keep original executable hash, configuration, target and launch checks; selection never starts a game or proves launch compatibility.
- Synchronize ten languages, paired READMEs and real App screenshots. Add isolated selection, persistence, discovery, resource-resolution and preflight regression checks; no live game/Guest acceptance.


- Native SwiftUI + AppKit interface: six pages (Dashboard, Environment, FX Manager, Game Performance, Logs, Settings), Cmd+1…6 navigation, dark/light/system appearance, and the official project icon.
- Bounded host/FX discovery and validated configuration editing with revision checks, backup and atomic replacement.
- Searchable, filtered, bounded and redacted logs, plus diagnostic report export.
- Read-only hardware detection (chip/CPU/GPU/memory/macOS) and current FX preference baseline comparison in Game Performance.
- GUI-driven FX/SSH actions: connect, read-only Guest inspection, original-entry FX/Steam start and the existing game-launch panel.
- Optional SSH/sudo credential remembering in a new App-owned Keychain namespace (session memory by default; old script Keychain items are untouched).
- Manual anonymous Native-release checks and a guarded signed-manifest download backend; official Sparkle remains the only installer. Appcast history is signature-verified before release preparation. Production automatic update installation remains unavailable without trusted distribution setup.
- Scoped, preview-confirmed FX 1.9.4 preference editing, verified backup/restore and external-change protection; stopped pinned FX required. Inferred recommendations remain read-only.
- Real English and Simplified Chinese screenshot sets, provenance hashes and documentation checks; the release-check Actions code is preserved as an inactive template under docs/ci.
- Native resources cover all ten original languages; translation naturalness still needs human review.

### Known limitations

- No signed/notarized installer or GitHub Release exists; `0.1.0` is a development preview.
- Safe FX stop/restart and validated automatic performance recommendations remain unavailable. Saved settings are not proof of runtime adoption; the original launch preflight may reject custom values.
- Ground missions, independent EAC acceptance and multiplayer remain unverified.
