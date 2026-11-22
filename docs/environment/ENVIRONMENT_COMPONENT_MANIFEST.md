# Environment component manifest

| Component | Source / identity | Integrity | Automatic action |
|---|---|---|---|
| FEX RF candidate | StonkGuy FEX PR 20, head `97583564c7983321f974f867eeab52bf25702079` | successful executable SHA-256 is locked in the baseline | **Blocked**: PR is open and no reviewed release archive exists |
| Proton-JE | `https://github.com/jegglest/proton-je/releases/download/proton-je-11.0-20261014-3/proton-je-11.0-20261014-3.tar.xz` | size 348245820; SHA-256 `aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485`; SHA-512 `fca903662898b5b117c926a7fa52f8053ff3c099a687c16851b15a81b2ad69bdecc4305962e67ddce2d0ec682c80ceffe59d601878894ef70a43529364747f25` | Enabled only for a matching baseline and a missing target; fixed HTTPS download, exact size/hash, bounded extraction, 5609 regular-file/1896 link inventory, critical hashes, atomic move and retained rollback |
| Vulkan / KosmicKrisp | FX 1.9.4 successful settings snapshot | exact strings plus successful session evidence | Detect and report; do not silently overwrite a nonmatching future FX layout |
| Launch options | successful runtime records | two managed assignments only | Additive merge with conflict stop and rollback receipt |
| IPv6 | diagnostic result | no success dependency established | Diagnostic only; never an automatic operation |

No alternate FEX, Proton, renderer, or network proxy is an approved substitute.

## 内置优先实施清单 · 2026-11-16

上表保留现有实现状态。新版目标为 RF FEX 与配置模板内置优先，RF 允许受信下载备用；Proton-JE 和 SteamLinuxRuntime_4 自动下载，原有 SteamLinuxRuntime_4-arm64 保留。

[逐文件 JSON 清单](../../native-app/Resources/deployment-components-v1.json) 的 `localTestOnly` 记录已有样本名称、字节数、SHA-256 和已知取样来源。准确构建版本、完整产物来源及公开再分发资格为 **UNVERIFIED**。其中 VERSIONS.txt 有 stage 记录，正式成功环境的安装目录未观察到该文件。现有样本哈希不承诺等同于未来批准的发行资源。

`plannedBundlePath` 是拟议的 Bundle 相对路径，`guestInstallPath` 是 SteamOS 目标。`plannedDeployment` 和 `rollback` 记录预期事务。现行 `bundled` 清单及各样本的 `bundled: false` 仍记录实际交付状态。备用源、完整伴随依赖及最终包清单尚待确认。发布校验不得把新增规划字段当作资源批准。

## 2026-11-22 实现核对

- 公开 App Bundle 携带配置、补丁、许可文本和清单。构建门禁核对已声明的文件大小和 SHA-256，并拒绝未批准的 RF 目录内容。

- 本机受控 Debug 另有完整的 [41 文件清单](../../native-app/Resources/rf-fex-debug-manifest-v1.json)。公开分发仍受许可与来源审核门禁约束。
- FEX 上游及固定 fork 提交的根许可证为 MIT，但这不足以证明历史完整二进制、辅助文件、子模块及依赖的可复现来源和公开再分发资格。PR 20 仍未形成已审核发布归档。因此不得把历史测试盘文件加入公开包。
- 受控 Debug 优先校验固定清单和所有文件，再使用既有备份、切换及回滚事务。已经安装的 App 管理树只有在与受控 Bundle 文件树精确匹配并通过运行探针后，才可跳过重新部署。
- 公开 `APP_BUNDLE` 与 `VERIFIED_DOWNLOAD` 均待批准。无已批准来源时报告 `RF_BUNDLE_PAYLOAD_UNAVAILABLE`。
