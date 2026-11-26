# Proton-JE Redistribution Audit

Date: 2026-11-26  
Version: `11.0-20261014-3`  
Build: `1792806463`

## Decision

The retained archive is the upstream release asset and is approved for redistribution only when its notices and corresponding source are shipped as required by the component licenses. No additional informal author approval is required for rights already granted by those licenses.

Stable inclusion is not yet approved: the independently verified corresponding-source archive must be published beside the binary, and the exact binary archive must pass real Guest deployment and runtime acceptance. Until those conditions pass, the component is `RC_ONLY_PENDING_SOURCE_PUBLICATION_AND_LIVE_ACCEPTANCE`; the fixed upstream HTTPS download remains the non-manual fallback.

## Binary provenance

| Field | Verified value |
| --- | --- |
| Upstream repository | `https://github.com/jegglest/proton-je` |
| Release tag | `proton-je-11.0-20261014-3` |
| Annotated tag object | `85bc204630f89d77ec7c0bd9e2732e46712bd5b8` |
| Tagged commit | `a69793ad2c48dbdf0299e5ef3264b99edb96eeda` |
| Archive | `proton-je-11.0-20261014-3.tar.xz` |
| Bytes | 348,245,820 |
| SHA-256 | `aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485` |
| Upstream SHA-512 | `fca903662898b5b117c926a7fa52f8053ff3c099a687c16851b15a81b2ad69bdecc4305962e67ddce2d0ec682c80ceffe59d601878894ef70a43529364747f25` |
| Base Proton commit | `7a94df49e4695fc101fd47d614166e69c43d9669` |
| Wine commit | `d360cd46d58bf6d2601dba414e0f84ad3ec0bd98` |
| Build method | Upstream tag workflow, Valve SDK container, `make redist` |

The local size and both digests equal the upstream Release metadata and checksum file. The archive's internal `version` file is `1792806463 proton-je-11.0-20261014-3`; `toolmanifest.vdf` requires Steam Runtime AppID 4183110.

## Corresponding source

The tagged repository and all 62 recursive submodules were checked out at their recorded object IDs. `native-app/Resources/proton-je-11.0-20261014-3-source-lock.json` records every path, origin and commit; its SHA-256 is `eae02108934ac7843d827b20c2eb644f7b1af929b83d8c6dc0e80444c675d0c4`.

The generated `proton-je-11.0-20261014-3-corresponding-source.tar.xz` is 422,456,272 bytes with SHA-256 `d5f7e56ea9911f8bab985a3b80492e76ee0e07a62ba2a3dec3507cf75e615c61`. Independent archive inspection found 90,861 entries, exactly one `CORRESPONDING_SOURCE_LOCK.json`, no `.git` metadata, and no absolute or parent-traversal paths. The release procedure requires this exact file as a co-located public asset. A source URL list alone is not treated as completion of the LGPL/GPL source obligation. The binary cannot move from RC-only to Stable-approved until public availability is recorded.

## License obligations

The upstream binary archive includes a 20,069-byte consolidated `LICENSE` and `LICENSE.OFL`. It grants BSD-3-Clause rights for the Proton top level and reproduces notices for Wine, DXVK, vkd3d-proton, FAudio, GStreamer, fonts, wine-mono, wine-gecko, OpenVR, orc, Rust libraries, AMD AGS, jxrlib and dav1d.

Key obligations are:

- reproduce the BSD/MIT/zlib/Apache/OFL notices and disclaimers;
- provide corresponding source for LGPL/GPL-covered built components and preserve the applicable license texts;
- preserve MPL 2.0 source availability for wine-gecko;
- retain font copyright and OFL text;
- do not use upstream names to imply endorsement;
- keep the exact binary and source identities together in release metadata.

The App must not extract, remove or replace the archive's license files. The project-level notice must point users to the co-located source asset and exact lock.

## Compatibility and distribution status

| Check | Result |
| --- | --- |
| Upstream release identity | PASS |
| Local SHA-256 and upstream SHA-512 | PASS |
| Tagged source commit | PASS |
| 62 recursive submodule identities | PASS |
| License/notice inventory | PASS |
| Corresponding-source working tree | PASS |
| Corresponding-source archive/hash | PASS |
| Public source asset availability | NOT_TESTED |
| Real App Guest deployment | NOT_TESTED |
| Proton run probe and Steam recognition | NOT_TESTED |
| HELLDIVERS 2 compatibility | NOT_TESTED |

No version upgrade was performed. The reviewed archive and existing deployment transaction remain unchanged.
