[简体中文](CHANGELOG.zh-CN.md) | English

# Changelog

All notable changes to the HELLDIVERS 2 FX Launcher Native App are recorded here, newest first. Unreleased entries have no release date. This file is the single source of truth for user-facing release notes; the README summary, GitHub Release notes and the future Sparkle appcast reuse this reviewed text. Do not paste raw, unreviewed Git commit messages into it.

No official release has been published yet. The current Native App version `0.1.0` (build `2026110602`) is a development preview, not a downloadable package.

## Unreleased

- Ensure bundled network launch resources are executable and reject non-executable resources before starting FX.

- Fix the actual Steam API mismatch without clearing independent launch-option reads; show technical failures and distinguish a verified Proton package from an unverified or conflicting installation.
- Verify the upstream SHA-512 checksum in addition to SHA-256 and the full inventory. After configuration confirmation, gracefully reboot the FX VM once, reconnect and authenticate SSH, verify the expected machine/boot transition, then apply Steam settings. Live reboot/write acceptance remains pending.

- Restore process-memory-only SSH/sudo credentials for the verified-environment candidate. Remove the encrypted credential files and restart restoration added by the superseded candidate; target/session changes clear both roles.

- Use 127.0.0.1:2222 and user steamos without manual entry; blank SSH fields preserve current values and only populated changed fields are saved.

- Install the exact missing Proton-JE target from a pinned upstream archive with full inventory verification while Steam remains running; configure HELLDIVERS 2 launch options through Steam’s live API and select the verified compatibility tool after Steam discovers it. Detection stays read-only; configuration confirmation, game guards and receipt recovery remain required. Live SteamOS acceptance is pending.

- Replace the global first-run Steam shutdown requirement with per-operation deferral of Steam-managed file writes, manual SteamOS Properties guidance, and an explicit no-automatic-changes explanation. Game, artifact and offline write guards remain. Live SteamOS validation and refreshed screenshots are pending.

- Separate detected components from deployment permissions; show unknown evidence neutrally, keep IPv6 advisory and non-blocking, and discover Proton-JE across bounded tool directories without executing candidates.

- Passed component detections remain green independently of unrelated deployment restrictions.

- Remove FX/SteamOS version allowlists from first-run setup and FX performance editing; retain actual capability, architecture, identity, artifact, backup and write-safety checks. Version changes during an approved transaction still invalidate that transaction.

- Superseded candidate history: an earlier build remembered verified SSH/sudo passwords in installation-local encrypted files. The current verified-environment candidate removes that behavior and does not migrate or read those files.

- First-Run Setup now uses the same local FX copy eligibility as launch; intact local test copies no longer fail the entry check solely because they lack an official publisher signature. Guest authentication and deployment profile/artifact checks remain separate.

- Show local FX test copies using the custom test identity and allow their intact locally signed bundles to launch through normal confirmation. Preserve target/process/SSH binding and distinguish local copies from publisher-verified builds.

- Remove the duplicate First-Run Setup shortcut above the Dashboard hero; keep setup accessible from the sidebar.

- Automatically close the game launch sheet when the current launch completes with a detected game process. Keep failed, cancelled and unverified launches open for inspection.

- Add host, port and user fields under Settings → SSH connection settings, with guarded saves and session credential invalidation. Candidate only; actual Chinese/English settings captures checked, live connection validation pending.
- Fix duplicate selected FX entries in automatic discovery; correct current seven-page documentation. Real Guest/game and distribution acceptance remain pending.

- Isolated First-Run Setup development build: actual environment detection, versioned profiles, reviewable plans, durable receipts, offline Steam VDF transactions and drift-guarded recovery, with ten-language UI. Credentials are process-memory only; compatibility checking no longer changes IPv4 configuration. FEX/Proton distribution is blocked pending reviewed artifacts; fresh VM/game/EAC/multiplayer remain untested. Latest is unchanged.

- SteamOS network candidate: runtime IPv6 moved to Environment with explicit preview, confirmation, independent sudo authentication, full-interface backup and recovery. Game startup no longer writes or requires IPv6.
- Added bounded read-only VM, verified Steam TLS, Guest PlayFab and STUN/UDP diagnostics, ten-language UI and Python parity audit. Real Guest writes/gameplay remain unverified; no Latest publication.

### Memory-only candidate (not released)

- Replace credential-vault access and remember/delete/authorize controls with independent SSH/sudo session credentials and explicit provided/verified/failed states. Existing saved items are never read, migrated or deleted.
- Consolidate the UI simplification branch while retaining the 1188d59 sudo quoting repair. Each approved privileged SSH call now authenticates independently without cross-session timestamp assumptions, with password-free argv/env and detached command stdin.
- Bind credentials to canonical FX/executable/config/process evidence and verified Guest boot; clear on identity change/loss or exit.
- Require exact-change approval and backup/recovery receipts for Guest IPv6 changes; manual restore re-verifies boot, identity and current values. Historical Steam login alone no longer establishes Steam readiness.
- Candidate only: live authentication/configuration/game acceptance remains unverified; no Latest update or main merge.

- Fix remote sudo empty-prompt shell quoting and distinguish missing credentials, rejected authentication, policy denial, transport and command failures. Live passworded sudo acceptance and a replacement App release remain pending.
- Remove the shared FX status bar from all six pages without a replacement or placeholder. Preserve the sidebar, page styling, FX detection/management and launch services; content fills the available top area.

- Read-only SSH diagnostics also recognize the selected FX publisher-sealed stock gvproxy after signature, stable-content and process-ancestry verification. Game launch continues to require the pinned bundled networking backend.

### Added

- Settings → About includes App/build/Core versions, full source commit, build timestamp and actual running path, with copy support. Environment includes read-only SSH diagnostics with effective endpoint, authentication and Guest identity stages.

### Fixed

- Correct duplicate OpenSSH executable in argv, establish the controlling terminal required for GUI password prompts, pass secure credentials to SSH diagnostics, and distinguish connection refusal, timeout, authentication, host-key and protocol failures. Preserve FX identity checks and host-key verification. Live Guest acceptance remains pending.

### Fixed

- FX instance identity false positive: trim the `ps` command-column padding and normalize the one-supervisor/one-VM-child FX topology, so the selected FX is recognized as the same instance instead of `FX_INSTANCE_MISMATCH (different_fx_copy)`. Genuinely different copies still fail closed and now report the selected and running paths.


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
- Historical preview implemented optional credential remembering; superseded by the memory-only candidate above. No current credential-store access remains.
- Manual anonymous Native-release checks and a guarded signed-manifest download backend; official Sparkle remains the only installer. Appcast history is signature-verified before release preparation. Production automatic update installation remains unavailable without trusted distribution setup.
- Scoped, preview-confirmed FX 1.9.4 preference editing, verified backup/restore and external-change protection; stopped pinned FX required. Inferred recommendations remain read-only.
- Real English and Simplified Chinese screenshot sets, provenance hashes and documentation checks; the release-check Actions code is preserved as an inactive template under docs/ci.
- Native resources cover all ten original languages; translation naturalness still needs human review.

### Known limitations

- No signed/notarized installer or GitHub Release exists; `0.1.0` is a development preview.
- Safe FX stop/restart and validated automatic performance recommendations remain unavailable. Saved settings are not proof of runtime adoption; the original launch preflight may reject custom values.
- Ground missions, independent EAC acceptance and multiplayer remain unverified.
