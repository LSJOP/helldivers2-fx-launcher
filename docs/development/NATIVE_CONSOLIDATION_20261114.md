# Native consolidation checkpoint — 2026-11-14

Candidate branch: integration/native-app-consolidation. Main promotion remains blocked.

## Integration

Base origin/main 478d2bf. Scoped release branch differences retain main repository layout and AGENTS. Brand commit 6e93460 adds ten bundle names; conflicts retain release updater, credential and packaging logic. Recovery adds helper registration validation and dispatch-time FEX re-probe; release per-App SSH tunnel isolation remains. Development and release-preparation dirty changes remain preserved and require remaining unique-difference review.

UpdateConfiguration now supplies the Sparkle delegate feed, retaining the validated GitHub stable URL. Regression checks distinguish GitHub and Pages and reject unconfigured preview.

Historical encrypted credential implementation was removed during the broad environment rewrite 0d2496a. Its commit message gives no security-specific rationale. Reuse the release version with installation-random AES-GCM key, independent target/role binding, owner-only files, link checks and durable rejection markers. No Keychain access. Isolated checks do not establish live authentication acceptance.

## Protection

Backups: sibling Backups/consolidation-20261114-120725 contains refs/log, per-worktree path/status, staged and unstaged binary patches, and untracked tar archives. Full bundle failed because partial-clone historical blobs were missing and GitHub timed out. Original objects, refs, stash and worktrees remain untouched. No branch, tag or worktree deleted.

## Remaining gates

Full check script fails screenshot provenance after branding UI changes. Real ten-language captures and visual review remain pending; do not replace fingerprint to claim acceptance. Signed production feed, trusted key configuration and actual updater replacement/rollback/relaunch remain unverified. No signature bypass.

Real FX/FEX setup and recovery, fresh Guest setup, SSH/sudo password matrix, Proton/game chain, independent IPv6 and performance matrix require user hardware acceptance. Safe SteamOS stop/restart remains unavailable without a verified backend. No Guest, FEXRootFS, Proton, Steam or macOS network writes performed.

Native Swift Core is the current implementation; Python isolated/static checks do not establish historical Python Core runtime coverage. No public release, tag or publication.

## Branch retention

All non-ancestor branches, active worktree branches, integration branch, main and legacy-script must remain. Ancestor-only candidates below still require dependency checks; none are authorized for deletion in this task.

- origin: ancestor of current main; review later
- origin/chore/repository-layout-20261114: ancestor of current main; review later
- origin/docs/auto-merge-policy-20261114: ancestor of current main; review later
- origin/docs/readme-changelog-policy-v1: ancestor of current main; review later
- origin/docs/v1-release-preparation-20261113: retain; not fully integrated
- origin/docs/v1-release-readme-sync: ancestor of current main; review later
- origin/feature/full-swift-native-migration: ancestor of current main; review later
- origin/feature/local-encrypted-credentials-20261105: ancestor of current main; review later
- origin/feature/localized-app-brand-20261114: retain; not fully integrated
- origin/feature/macos-native-app: ancestor of current main; review later
- origin/feature/native-app-performance-v2: ancestor of current main; review later
- origin/feature/native-app-ux-v2: ancestor of current main; review later
- origin/feature/native-first-run-20261104: ancestor of current main; review later
- origin/feature/native-fx-selection-v21: ancestor of current main; review later
- origin/feature/native-localization-recovery-20261103: ancestor of current main; review later
- origin/feature/native-recovery-20261112: retain; not fully integrated
- origin/feature/proton-je-auto-install-20261106: ancestor of current main; review later
- origin/fix/native-launch-resources-20261103: ancestor of current main; review later
- origin/fix/steam-live-api-20261106: ancestor of current main; review later
- origin/fix/steamos-setup-steam-running-20261106: ancestor of current main; review later
- origin/integration/native-main-20261103-v2: ancestor of current main; review later
- origin/legacy-script: retain; not fully integrated
- origin/main: ancestor of current main; review later
- origin/release/v1.0.0-integration: retain; not fully integrated
- origin/ui/remove-global-fx-bar-20261104: ancestor of current main; review later
