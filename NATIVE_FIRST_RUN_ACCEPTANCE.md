# First-run acceptance

Development scope: isolated source/build only. No current successful SteamOS changes, new VM creation, Latest replacement, main merge or release.

| Status | Result |
| --- | --- |
| IMPLEMENTED | SwiftUI wizard, real host/SSH detector, versioned profile, reviewable plan, exact consent, executor, receipts, selective safe recovery, FEX/Proton/FX/Steam/network adapter interfaces |
| VERIFIED | See NATIVE_DEPLOYMENT_TEST_RESULTS.md for exact isolated checks and build evidence |
| BLOCKED | Reviewed distributable FEX/Proton artifacts and clean installed-tree manifests; package/download UI activation; unsupported archive formats and version combinations |
| NOT_TESTED | Clean official FX 1.9.8 + recorded SteamOS VM; full Native deployment; compatibility tool recognition; real game/official EAC chain; independent multiplayer; live repeated install and restore |

The final ordinary-user one-click deployment acceptance is **not achieved** while required artifacts and new-VM testing are blocked. The build is a reviewable development implementation, not a production installer. Completion of approved configuration items never means that blocked components were installed. The UI retains blockers after partial success and asks for rescan.

Future live acceptance requires the user's explicit authorization and an independent official VM, without personal disk/Prefix cloning. Record initial state, exact target/profile/artifact hashes, real installation receipts, repeat behavior and recovery. Validate gameplay, official EAC and multiplayer separately. Do not substitute any local tests for these results.
