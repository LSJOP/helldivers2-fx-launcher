# FEX dynamic compatibility acceptance

Test date 2026-11-14, Asia/Shanghai. Runtime implementation commit `7d9df28`, following `b4be9cf` and `0b02a53`. This candidate has incomplete gameplay acceptance.

## Implementation

The old launch guard required the historical executable digest `ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf`. Detection also used `FEX --version` after that match. The installed Steam build interprets `--version` as a program name and reports command not found. These predicates could reject an executable that can run x86-64 code.

Detection now checks the Steam FEX directory, ARM64 ELF header, executable permissions, emulator registration and declared helper entry points. It inventories the complete bounded tree, rejecting unsafe links, special files and privileged modes. An unknown build requires explicit confirmation before execution. Consent binds the full tree to the FX executable, canonical FX path, Guest machine and SSH connection identity. Changed files require fresh confirmation. Consent persists separately from encrypted passwords and never changes provenance to verified.

The runtime probe creates a temporary freestanding x86-64 ELF that exits with 42. It executes through the installed FEX with a 12-second subprocess timeout, suppresses binary output and disables disk caching. It verifies Guest boot and inventories the tree again afterward. Actual Proton/game integration remains a separate launch test. Locally built candidates retain pinned source/patch provenance, exact manifests, transactional backups and guarded recovery. Their executable digest no longer has to reproduce the historical digest.

Home and First-Run Setup use the existing common workflow. The direct launch action also enforces fresh FEX checks. Before game dispatch it rechecks FEX and host identity without repeating the full Proton inventory. The bounded game-process wait is now ten minutes to accommodate Steam's first-launch setup. No FEX file, VM, game installation or password was replaced during these tests.

## Upstream and installed environment

Reviewed [steamac](https://github.com/fxgl/steamac) and [FEX](https://github.com/FEX-Emu/FEX). steamac uses an ARM64 SteamOS VM with libkrun and a Steam-managed FEX compatibility tool. Its runtime and graphics integration require inspecting the installed Steam layout.

Observed FX version `1.9.12`. FEX is installed at `/home/steamos/.local/share/Steam/steamapps/common/FEX-Emu`. Steam AppID `3127680` reports build `24136555`. Its emulator registration points to `./usr/bin/FEX`, `./FEXCompatTool` and `./usr/bin/FEXServerManager`. Steam's actual game chain uses `fex-compat-tool`, `SteamLinuxRuntime_4` and `proton-je-11.0-20261014-3`. Upstream provenance of this installed FEX has not been established, so a custom build cannot be asserted from the hash difference alone.

Observed executable SHA-256 `f9cbb7a70e804b9930fed02fd9d1349d49d7808faace703063a9b4944bc3568e`. Observed full-tree fingerprint `542e2e4ea1d488f8952f937005e4bdd497b9cbddcaa231a7feadc1177f9831a2`. The historical successful-gameplay fingerprint remains historical evidence and does not validate this installed build. Steam-managed updates can change these files and invalidate the confirmation.

## Real acceptance

| Check | Observed result |
| --- | --- |
| FX and SSH | Passed through the Home workflow with existing saved credentials |
| sudo | Historical success retained. This run required no privileged changes and did not independently exercise sudo |
| Installed FEX basic execution | Passed with exit 42, including the final production probe with registration checks |
| Origin confirmation | Displayed in the real App. User explicitly approved this installed build |
| FEX status | Real App displayed compatibility mode, with provenance unverified |
| Proton, Steam tool and managed launch options | Home refreshed the common plan and completed environment verification, reaching step 5 of 6 |
| Home game request | Steam received AppID 553850 at 02:14:32 |
| First-launch preparation | Steam checked shader depots, then ran its DirectX install scripts until 02:19:30 |
| Initial App process wait | Ended after three minutes before Steam finished preparation. The candidate now allows ten minutes, bounded by the overall operation timeout |
| Actual protected launch chain | Steam created wrapper processes at 02:19:31 and removed them at 02:19:39 |
| `helldivers2.exe` | Not observed |
| Main menu | Not reached |
| Anti-cheat initialization | Unverified |
| Single-player mission | Not reached |
| Multiplayer / joining another player | Not reached |

Steam's output reports `Invalid or Unsupported elf file` and an empty RootFS path. Read-only inspection confirms `/usr/share/guestos/fex-mesa` exists, and the per-game FEX configuration names that directory. The generic error therefore does not establish a missing RootFS installation. The installed FEX passes the minimal probe while the Proton/game chain fails. Determining the exact loader/re-exec failure needs further investigation. Replacing the existing FEX requires a separately reviewed candidate and explicit confirmation under the user's environment-protection requirement.

The latest Release was opened for a second GUI test of the standalone setup entry. An SSH tunnel left by the terminated Debug test process initially occupied port 18094. The exact old task-owned master was identified and closed, then setup was retried. This recovery did not stop Steam or FX. The retry in the actual `7d9df28` Release reached 100% and displayed environment setup complete with FEX compatibility mode. No password entry or repeated build-confirmation prompt was required after restart. The longer game wait was compiled and covered by the core regression run; another game launch with that final Release was not attempted after the earlier integrated runtime failure.

## Automated verification and package

The full checks passed from a clean checkout of `b4be9cf`. This includes 150 deployment checks, 19 FX identity checks, 27 core integration checks, 66 network checks, 35 SSH checks, 30 privileged-executor checks, 29 session credential checks, 31 encrypted-persistence checks, 23 launch/UI state checks and the Proton release suite. The new bundled probe has nine isolated filesystem/process tests and the candidate transaction suite has 13 tests. The expanded Native Core suite passed all 107 checks after the final launch-wait change. Ten languages passed localization validation. Documentation passed 15 checks, and the README screenshot gate passed 18 references. Real Chinese and English Home/setup captures were visually reviewed.

A clean arm64 Release built from `7d9df28` is at `绝地潜兵脚本/APP 版本/FEX-Compatibility-7d9df28/HD2FXNative.app`. Bundle/resource, arm64 architecture and ad hoc code-signature checks passed. The bundle secret-pattern scan passed with no findings. A separate whole-repository scan flags two existing credential-test literals in `CredentialChecks.swift` and `PersistentCredentialChecks.swift`; those are fixture strings, with no corresponding bundle finding. Ad hoc signing does not establish notarized distribution.

## Integration status

Development branch `feature/native-recovery-20261112`. Gameplay acceptance remains incomplete, so this task does not satisfy the requested main-merge conditions. No formal release was published. Pre-existing uncommitted README, locale and other-page work was preserved through partial staging.
