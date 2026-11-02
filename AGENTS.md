# Native App development

Instruction version: **v1.0.1** · Updated: **2026-11-02**.
Change: adopt GitHub migration, minimal testing and prompt versioning rules.

- Architecture: SwiftUI + narrowly scoped AppKit; one AppState and existing Service Layer. Phase 1 is read-only. Unknown/unverified is never success. Do not start games or alter FX, Guest, SSH, Keychain, Steam, FEX, Proton or real user settings without explicit task authorization.
- Work on `feature/macos-native-app`; batch related changes, verify the affected behavior, commit and push the feature branch. Merge substantial completed stages into main only after appropriate checks. Never force-push, rewrite unknown history, delete releases/tags, or overwrite another developer's changes.
- `legacy-script` preserves original launcher history. `native-app/CoreSnapshot` is a pinned submodule of this repository's archive branch. Its read-only compatibility snapshot is build input, not an active game launcher. Do not silently advance it or execute archived entrypoints.
- Locate relevant files/symbols with rg. Reuse confirmed context; do not repeatedly scan or print the whole repo, large logs or solved investigations. Prefer incremental edits over unrelated refactoring.
- Default workflow: batch edits → static checks → one appropriate build → necessary affected tests → brief report. No step-by-step confirmations for already authorized ordinary work.
- Level 1 (colors, fonts, spacing, static layout/text/translations/assets): static checks first; one grouped verification when useful. Do not compile/launch after every edit or repeatedly launch for screenshots.
- Level 2 (page logic, settings/state, ordinary modules/migration): build once after the related changes; test only affected behavior.
- Level 3 (game/CrossOver integration, filesystem, permissions, updates, GitHub release): necessary build and safety/functional checks plus regression proportional to impact. Never skip critical verification to save budget.
- Diagnose failures from existing logs, fix related issues together, and rerun only when a change or new evidence justifies it. Report unverified behavior honestly; never invent success.
- No per-file audits, per-feature acceptance documents, repeated full UI sweeps, evidence ZIPs or redundant Markdown. Keep only useful stage documentation. Do not spawn agents without a concrete need and authorization. Use lower reasoning settings for simple work if configurable.
- UI defaults to dark. Chinese functional labels and native Navigate menu show Chinese only; English mode shows English only. Preserve HELLDIVERS 2 / FX LAUNCHER marks and native shortcuts. Language/theme changes must not reset business state.
- Future priorities: UI polish → remaining localization → ten legacy languages → missing legacy capabilities → CrossOver → core validation → distribution. Do not start these automatically during repository migration.
- Large complete development instructions require independent semantic versions (`vMAJOR.MINOR.PATCH`). Rule/workflow/testing/GitHub/budget changes that update the complete instruction default to a patch increment; larger process changes increment minor/major appropriately. Ordinary code changes do not increment instruction versions. Never reuse/reset versions. Record only current version, date and a short change note in this file; do not duplicate full prompt history. Instruction and software versions are independent.
- Completion reports: completed work, GitHub branch state, necessary verification, real remaining issues, next direction. Keep them brief.

UI instruction: **HD2_NATIVE_APP_UI_REFINEMENT_v1.0.1** · 2026-11-02. Five-page tactical visual system; a large standalone licensed soldier asset is Dashboard-only. Environment, FX, Logs and Settings share one small upper-right wireframe globe. Never use a whole UI preview as artwork or copy its example health states. Keep absent metadata explicit.
