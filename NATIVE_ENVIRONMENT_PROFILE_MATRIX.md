# Environment profile matrix

Bundled profile: `native-app/Resources/environment-profile-v1.json`, ID `hd2-fx198-steamos045-aarch64`, schema/profile version 1, FX 1.9.8, SteamOS 0.4.5, aarch64, HELLDIVERS 2 AppID 553850. Version mismatches produce Unsupported. This is a historical candidate, not a universal distribution baseline.

| Item | Class | Policy / evidence |
| --- | --- | --- |
| Steam / HD2 | REQUIRED | Actual file evidence; no automated store/game installation |
| FEX RF | CONDITIONAL | Historical candidate; ce93cada… is only one fingerprint, never full readiness |
| Proton-JE 11.0-20261014-3 | CONDITIONAL | Full release inventory required; five Wine files or ntdll alone are insufficient |
| Vulkan / KosmicKrisp | CONDITIONAL | Kernel/host selection evidence separated from actual rendering |
| FEX_NEEDSSECCOMP=1 / FEX_DISKCACHE=0 | CONDITIONAL | Historical FEX combination; only reviewed managed launch assignments |
| VKD3D single_queue / taskset | OPTIONAL | Historical performance choices; preserved when present, not forced |
| Guest IPv4-only | OPTIONAL | Not proven universally necessary; default preserve |
| gvproxy-eim | UNKNOWN | Actual host ancestry inspected; UDP/NAT/matchmaking acceptance separate |
| HTTPS proxy | CONDITIONAL | User/network dependent; no hardcoded gateway/port |
| CPU/RAM/GPU budget, HUD, MetalFX | OPTIONAL | Existing hardware/version-scoped Performance page; no universal 8/8192/6144 target |

Sources: supplied 2026-11-04 SteamOS trace, historical operations audit, fixed FX 1.9.8 release link in the JSON. Licenses/build provenance are explicitly pending for FEX/Proton redistribution. `artifacts: []` intentionally blocks distribution and full-manifest installed-state acceptance. No fresh official SteamOS image baseline or clean Prefix is claimed. A future reviewed artifact needs component/version/HTTPS source/archive hash/full file hash list/license/build record. The strict importer rejects unsupported archive features before deployment.
