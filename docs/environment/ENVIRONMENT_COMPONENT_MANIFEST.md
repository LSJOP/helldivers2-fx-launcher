# Environment component manifest

| Component | Source / identity | Integrity | Automatic action |
|---|---|---|---|
| FEX RF candidate | StonkGuy FEX PR 20, head `97583564c7983321f974f867eeab52bf25702079` | successful executable SHA-256 is locked in the baseline | **Blocked**: PR is open and no reviewed release archive exists |
| Proton-JE | `https://github.com/jegglest/proton-je/releases/download/proton-je-11.0-20261014-3/proton-je-11.0-20261014-3.tar.xz` | size 348245820; SHA-256 `aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485`; SHA-512 `fca903662898b5b117c926a7fa52f8053ff3c099a687c16851b15a81b2ad69bdecc4305962e67ddce2d0ec682c80ceffe59d601878894ef70a43529364747f25` | Enabled only for a matching baseline and a missing target; fixed HTTPS download, exact size/hash, bounded extraction, 5609 regular-file/1896 link inventory, critical hashes, atomic move and retained rollback |
| Vulkan / KosmicKrisp | FX 1.9.4 successful settings snapshot | exact strings plus successful session evidence | Detect and report; do not silently overwrite a nonmatching future FX layout |
| Launch options | successful runtime records | two managed assignments only | Additive merge with conflict stop and rollback receipt |
| IPv6 | diagnostic result | no success dependency established | Diagnostic only; never an automatic operation |

No alternate FEX, Proton, renderer, or network proxy is an approved substitute.
