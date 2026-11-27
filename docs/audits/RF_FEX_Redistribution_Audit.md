# RF FEX Redistribution Audit

Date: 2026-11-26

Scope: `eac-main-20261022-historical`, retained 41-file controlled payload

Historical payload: 26,327,173 bytes; tree SHA-256 `0ddd70d9b19e0a6abac26d9edb442fe43557376670c46d9489890f7eef913cd7`

## Decision

The FEX-derived binaries, thunks, generated data and the three byte-identical Steam templates are approved for redistribution with the FEX MIT notice and the dependency notices listed in [Third_Party_License_Inventory.md](Third_Party_License_Inventory.md). The MIT grant permits source and binary redistribution; it does not require a separate author approval.

This conclusion does **not** approve two files recovered from an installed Steam tool:

| File | Finding | Release treatment |
| --- | --- | --- |
| `fex-compat-tool` | No license header and no authoritative public source mapping was found. The reviewed copy was derived from a Steam installation. | Excluded. Replaced by the project-owned, source-reviewed `native-app/Resources/rf-fex-release/fex-compat-tool`. |
| `unshare.py` | No license header or authoritative source mapping; imported by the recovered wrapper but never called. | Excluded without replacement. |

The release candidate therefore uses 39 retained FEX files, one project-owned wrapper and `LICENSE-FEX.txt`: 41 files, 26,325,773 bytes, tree SHA-256 `79c051c4e5523513dcb5e030ac466f9b3941551e4f3109132e775b886596fbcd`. The generated manifest SHA-256 is `f491ba43783d986a183592bb5fb7f3f0fc4b338e80c8b3f1089a764914135bca`.

Distribution rights and runtime acceptance are separate. The rights review is approved; Stable inclusion remains blocked until the changed wrapper and complete tree pass real Guest deployment, execution, two-reboot persistence and game-launch acceptance.

## Source and build evidence

- Source family: `StonkGuy/FEX`, pinned commit `87c57f0a5f2a0e87c6b994e9d91f72ac6d512ab8`.
- RF patch: `native-app/Resources/fex-rf-reviewed.patch`, SHA-256 `85999c4f3a82063c66095d5315a661f0eed8369ed7b4b03191ed5dc8521d7926`.
- Source license: MIT, retained as `native-app/Resources/LICENSE-FEX.txt`.
- Historical build records identify clang 19.1.7, a CMake/Ninja Runtime `DESTDIR` stage, `eac-main-20261022`, disk-cache format 36 and synthetic identity `e42baddf6fbf43a8286a21dd9a3abcd68b617f77`.
- All ten retained stage inputs match their historical SHA-256 values. The 28 companion files match `rf-replay-support/SHA256SUMS`.
- `ConfigTemplate.json`, `emulator.json` and `toolmanifest.vdf` are byte-identical to the same paths at the pinned source commit.
- The seven `usr/bin` programs, `FEXCompatTool`, GDB reader, thunk databases and host/guest thunk paths are declared by that source tree's CMake installation rules. ELF names, architectures, build IDs and FEX symbols agree with those targets.
- The historical synthetic identity is not a public Git commit. This limits bit-for-bit reproducibility of the old binaries, but it does not erase the MIT redistribution grant. The limitation remains recorded as provenance grade `HISTORICAL_STAGE_HASH_VERIFIED_SOURCE_FAMILY_MAPPED`, not falsely upgraded to a reproducible build.

## File-by-file classification

| Paths | Count | Source/right conclusion |
| --- | ---: | --- |
| `usr/bin/FEX`, `FEXBash`, `FEXGetConfig`, `FEXOfflineCompiler`, `FEXpidof`, `FEXServer`, `FEXServerManager` | 7 | FEX CMake Runtime outputs; MIT plus dependency notices; retained historical SHA-256 values. |
| `FEXCompatTool` | 1 | Built from `Source/Steam/CompatTool.cpp`; FEX MIT; historical SHA-256 retained. |
| `ConfigTemplate.json`, `emulator.json`, `toolmanifest.vdf` | 3 | Byte-identical to pinned FEX source; MIT. |
| `VERSIONS.txt` | 1 | Generated FEX build record; MIT-covered build output; historical identity retained verbatim. |
| `usr/lib/aarch64-linux-gnu/fex-emu/HostThunks/*` and `HostThunks_32/*` | 12 | FEX thunk targets; dynamically depend on Guest system libraries rather than redistributing those libraries; FEX/dependency notices apply. |
| `usr/share/fex-emu/GuestThunks/*` and `GuestThunks_32/*` | 13 | FEX guest thunk targets; MIT/dependency notices apply. |
| `usr/lib/aarch64-linux-gnu/gdb/libFEXGDBReader.so` | 1 | FEX `Source/Tools/FEXGDBReader` target; MIT/dependency notices apply. |
| `usr/share/fex-emu/ThunksDB.json` | 1 | FEX installed thunk database; MIT. |
| recovered `fex-compat-tool`, recovered `unshare.py` | 2 | Rights not established; excluded from release candidate. |
| project wrapper, `LICENSE-FEX.txt` | 2 | Project-owned wrapper plus required MIT notice; release-candidate replacements. |

The exact original 41 hashes and modes remain in `native-app/Resources/rf-fex-debug-manifest-v1.json`; the approval and deterministic overlay are bound in `native-app/Resources/distribution-approvals-v1.json`. The historical manifest is not rewritten, preserving the audit trail.

## Security review

- The assembler first verifies all 41 historical inputs and their tree fingerprint.
- It removes only the two named recovered files and overlays two hash-pinned tracked files.
- It rejects links, hardlinks, traversal, unexpected modes, extra files, oversized files and mismatched totals.
- Release code accepts only the compiled-in generated-manifest SHA-256.
- Steam Linux Runtime 4 remains outside the App and under Guest Steam management.
- No historical image or Guest installation was modified for this audit.

## Remaining acceptance

| Check | Result |
| --- | --- |
| Source/license grant | PASS |
| Historical 41-file hash verification | PASS |
| Unlicensed recovered files excluded | PASS |
| Deterministic 41-file release assembly | PASS |
| Real App deployment of replacement tree | NOT_TESTED |
| RF execution probe with replacement wrapper | NOT_TESTED |
| Two Guest restarts | NOT_TESTED |
| HELLDIVERS 2 / EAC / gameplay | NOT_TESTED |

The last four items are runtime release-acceptance blockers, not unresolved claims that the MIT license needs an extra author permission.
