# Rights and provenance

This is an unofficial launcher. HELLDIVERS 2 and related marks belong to their respective owners. No official endorsement is claimed. No official game artwork, fonts, runtime binaries, accounts, credentials or Guest images are bundled. The tactical graphic is code-drawn geometry.

The Dashboard illustration in `native-app/Assets.xcassets/HelldiverHero.imageset` is the user-supplied generated soldier image provided for integration on 2026-11-02. It is bundled unchanged, with layout gradients applied in SwiftUI. This records the supplied source and requested use; it does not claim a separate third-party redistribution license or ownership of depicted marks.

A project-wide source license has not been selected. Do not assume redistribution rights beyond the rights actually granted by each owner. The read-only Core snapshot is pinned in the legacy-script submodule; its historical provenance and unresolved licensing notes remain in that archive.

Sparkle 2.10.1 is integrated from the official sparkle-project/Sparkle package, pinned by Package.resolved. Its license and bundled third-party notices are retained in [Sparkle-LICENSE.txt](native-app/Localization/en.lproj/Sparkle-LICENSE.txt) and copied into the App resources. This dependency license does not grant a project-wide license to the Launcher.

The shared `SuperEarthSpaceHeader` artwork was supplied by the user for integration on 2026-11-02. The official project AppIcon was supplied on 2026-11-03 as a 1254×1254 PNG, then proportionally resized into macOS AppIcon slots without an additional rounded mask. The documentation icon is copied from a generated size of this same source. These supplied generated assets are not official game artwork licenses or a claim of ownership of related marks. Actual App screenshots render these assets alongside real UI; no generated UI mockup is presented as a runtime capture.

## RF FEX reviewed payload

The reviewed v1.0.7 candidate pins StonkGuy/FEX commit `87c57f0a5f2a0e87c6b994e9d91f72ac6d512ab8` and the historical PR20 core RF patch (SHA-256 `85999c4f3a82063c66095d5315a661f0eed8369ed7b4b03191ed5dc8521d7926`). The patch retains its original author and attribution. FEX is MIT licensed; the license is bundled as `LICENSE-FEX.txt`. The recovered Steam wrapper and unused `unshare.py` were excluded because no authoritative redistribution grant was established; the candidate uses a project-owned wrapper instead. The exact rights/provenance distinction and dependency notices are recorded in [the RF audit](docs/audits/RF_FEX_Redistribution_Audit.md) and [license inventory](docs/audits/Third_Party_License_Inventory.md). Source: https://github.com/StonkGuy/FEX/pull/20 .

## Proton-JE 11.0-20261014-3

The reviewed archive is the unmodified upstream release asset from `jegglest/proton-je`, tag `proton-je-11.0-20261014-3`, commit `a69793ad2c48dbdf0299e5ef3264b99edb96eeda`. It is 348,245,820 bytes, SHA-256 `aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485`, and upstream SHA-512 `fca903662898b5b117c926a7fa52f8053ff3c099a687c16851b15a81b2ad69bdecc4305962e67ddce2d0ec682c80ceffe59d601878894ef70a43529364747f25`.

The archive retains its consolidated `LICENSE` and `LICENSE.OFL`. Proton's top level is BSD-3-Clause and the archive includes components under LGPL, MPL, zlib, MIT, BSD, SIL OFL and other recorded terms. Any public binary distribution must include the corresponding-source archive fixed by `native-app/Resources/proton-je-11.0-20261014-3-source-lock.json`; external source links alone are not counted as completion of that obligation. See [the Proton-JE audit](docs/audits/Proton_JE_Redistribution_Audit.md) for the exact release identity and remaining Stable gates.

## Super Earth city banner

`SuperEarthCityCinematic.png` is the user-approved Plan A AI-generated concept artwork, supplied without the blue arc. The original supplied PNG is stored in the Xcode asset catalog. The Dashboard displays it with proportional clipping. Provenance and reference inventory are recorded in [Dashboard UI V002](docs/design/Dashboard_UI_V002/README.md). This concept artwork has no official game-art attribution.

## Super Earth command emblem

`super_earth_command_emblem.png` is the user-approved AI-generated gold emblem delivered as a transparent PNG attachment. The checked-in image retains the supplied attachment bytes. The original generation filename was unavailable on the Mac.
