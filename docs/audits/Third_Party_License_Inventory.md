# Third-Party License Inventory for v1.0.7 Candidate

Date: 2026-11-26

This inventory covers the newly reviewed RF FEX and Proton-JE payloads. It records license obligations, not gameplay acceptance or an endorsement by any upstream project.

## RF FEX payload

| Component/source | License | Release obligation/status |
| --- | --- | --- |
| FEX main source and `FEXCore` | MIT | Include copyright and permission text (`LICENSE-FEX.txt`). PASS. |
| tiny-json | MIT | Retain notice. PASS in inventory; source retained. |
| fmt | MIT | Retain notice. PASS in source lock/inventory. |
| unordered_dense | MIT | Retain notice. PASS in source lock/inventory. |
| cpp-optparse | MIT | Retain notice. PASS in source lock/inventory. |
| VIXL | BSD-3-Clause | Retain notice/disclaimer. PASS in source checkout. |
| jemalloc | BSD-2-Clause | Retain notice/disclaimer. PASS in source checkout. |
| range-v3 | Boost Software License 1.0 | Retain license text. PASS in source checkout. |
| rpmalloc | Public Domain / MIT option | Retain upstream notice. PASS in source checkout. |
| Tracy | BSD-3-Clause | Retain notice/disclaimer. PASS in source checkout. |
| xxHash | BSD-2-Clause | Retain notice/disclaimer. PASS in source checkout. |
| Zydis / Zycore | MIT | Retain notice. PASS in source checkout. |
| Vulkan-Headers | Apache-2.0 | Retain license and notices. PASS in source checkout. |
| drm-headers | MIT-style kernel/UAPI notices | Retain notices. PASS in source checkout. |
| SoftFloat-3e | BSD-style | Retain source notice/disclaimer. PASS in source checkout. |
| Cephes | BSD permission evidence in retained source | Retain notice and permission record. PASS in source checkout. |
| system `libc`, `libstdc++`, `libgcc_s`, GL/X11 and Guest driver libraries | External dynamic dependencies | Not copied into RF payload; detect/probe in Guest. |
| recovered Steam `fex-compat-tool` and `unshare.py` | No authoritative grant established | EXCLUDED from release candidate. |
| replacement `fex-compat-tool` | Project-owned | May be distributed by project owner; source ships in repository/App payload. |

## Proton-JE archive

| Included family | License recorded by upstream archive | Obligation |
| --- | --- | --- |
| Proton top level | BSD-3-Clause | Reproduce copyright, conditions and disclaimer; no endorsement. |
| Wine | LGPL-2.1 | Provide corresponding source and license; preserve user relinking/modification rights. |
| DXVK | zlib/libpng | Reproduce notice; identify modifications. |
| vkd3d-proton | LGPL-2.1 | Provide corresponding source and license. |
| FAudio | zlib | Reproduce notice. |
| GStreamer/base/good | LGPL-2.x | Provide corresponding source and license. |
| Liberation, Source Han Sans, Noto | SIL Open Font License | Include OFL and copyright; preserve reserved-name terms where applicable. |
| Ume fonts | permissive custom grant | Reproduce grant/disclaimer. |
| wine-mono and included libraries | MIT/LGPL/GPL-with-exception/BSD/MS-PL/zlib mix | Preserve full upstream notice; provide corresponding source for applicable copyleft portions. |
| wine-gecko | MPL-2.0 and component licenses | Keep source available and retain notices. |
| orc | BSD-style | Reproduce notices/disclaimers. |
| Rust GStreamer libraries | MIT | Reproduce consolidated notice. |
| OpenVR | BSD-3-Clause | Reproduce notice; no endorsement. |
| AMD AGS | MIT-style | Reproduce notice. |
| jxrlib | BSD-style | Reproduce notice. |
| dav1d | BSD-2-Clause plus AOM Patent License 1.0 | Reproduce notice and patent terms. |

The authoritative detailed text remains the `LICENSE` and `LICENSE.OFL` inside the unmodified upstream archive. The corresponding source lock fixes 62 recursive submodules and is part of the release approval evidence.

## Distribution decision matrix

| Payload | Rights | Provenance | RC inclusion | Stable inclusion |
| --- | --- | --- | --- | --- |
| Reviewed RF release tree | APPROVED_WITH_NOTICES | Historical hashes/source-family mapped; non-reproducible identity disclosed | Allowed for controlled RC | Pending real deployment/game acceptance |
| Proton-JE upstream archive | APPROVED_WITH_NOTICES_AND_CORRESPONDING_SOURCE | Exact upstream asset, SHA-256/SHA-512 verified | Allowed for controlled RC | Pending co-located source asset and real acceptance |
| Steam Linux Runtime 4 | Valve Steam-managed dependency | Steam AppID 4183110 | Not bundled | Not bundled |

Changing a boolean without satisfying the recorded evidence is not an approval. `native-app/Resources/distribution-approvals-v1.json` binds each decision to immutable hashes and explicit remaining conditions.
