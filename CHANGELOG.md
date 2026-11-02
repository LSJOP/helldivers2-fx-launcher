[简体中文](CHANGELOG.zh-CN.md) | English

## Unreleased — 2026-11-03

- Integrate FX selection V2 and automatic selection V2.1: one shared, persisted default for FX management, overview and launch. Auto-select a sole identity/path-verified candidate; preserve valid manual choices; revalidate missing, moved and updated installations.
- Pass the selected FX path to the guarded existing backend. Resolve helper/gvproxy resources separately and avoid repeated FX pickers. Keep original executable hash, configuration, target and launch checks; selection never starts a game or proves launch compatibility.
- Synchronize ten languages, paired READMEs and real App screenshots. Add isolated selection, persistence, discovery, resource-resolution and preflight regression checks; no live game/Guest acceptance.
