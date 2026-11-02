[简体中文](CHANGELOG.zh-CN.md) | English

# Changelog

All notable changes to the HELLDIVERS 2 FX Launcher Native App are recorded here, newest first. Unreleased entries have no release date. This file is the single source of truth for user-facing release notes; the README summary, GitHub Release notes and the future Sparkle appcast reuse this reviewed text. Do not paste raw, unreviewed Git commit messages into it.

No official release has been published yet. The current Native App version `0.1.0` (build `1`) is a development preview, not a downloadable package.

## Unreleased — 2026-11-03

### Added

- Native SwiftUI + AppKit interface: six pages (Dashboard, Environment, FX Manager, Game Performance, Logs, Settings), Cmd+1…6 navigation, dark/light/system appearance, and the official project icon.
- Bounded host/FX discovery and validated configuration editing with revision checks, backup and atomic replacement.
- Searchable, filtered, bounded and redacted logs, plus diagnostic report export.
- Read-only hardware detection (chip/CPU/GPU/memory/macOS) and current FX preference baseline comparison in Game Performance.
- GUI-driven FX/SSH actions: connect, read-only Guest inspection, original-entry FX/Steam start and the existing game-launch panel.
- Optional SSH/sudo credential remembering in a new App-owned Keychain namespace (session memory by default; old script Keychain items are untouched).
- Sparkle 2 update integration for the Launcher only (feed/signing service not configured; checks remain disabled).
- Ten original locale catalogs retained; new Native translations are partial with English fallback.

### Known limitations

- No signed/notarized installer or GitHub Release exists; `0.1.0` is a development preview.
- Safe FX stop/restart and writable inferred performance profiles are not implemented (Apply/Restore are disabled).
- Ground missions, independent EAC acceptance and multiplayer remain unverified.
