[简体中文](CHANGELOG.zh-CN.md) | English

# Changelog

All notable changes to the HELLDIVERS 2 FX Launcher Native App are recorded here, newest first. Unreleased entries have no release date. This file is the single source of truth for user-facing release notes; the README summary, GitHub Release notes and the future Sparkle appcast reuse this reviewed text. Do not paste raw, unreviewed Git commit messages into it.

No official release has been published yet. The current Native App version `0.1.0` (build `1`) is a development preview, not a downloadable package.

## Unreleased

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
