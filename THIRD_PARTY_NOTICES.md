# 第三方组件、素材与许可证 / Third-party components, artwork and licenses

[README](README.md) · [贡献 / Contributing](CONTRIBUTING.md)

## 简体中文

核对日期：2026-10-29。此次核对的是上游许可文件、当前文件清单与已有素材来源记录，**不是对完整运行包的再分发授权确认**。没有为本项目新增或选择 `LICENSE`，也没有加入第三方运行二进制。

### 项目源码

本仓库尚未确定覆盖所有启动器文件的整体源码许可证。现有源码、第三方调用封装、补丁和衍生素材的来源需要逐项确认；不能因为 GitHub 可见或某个依赖采用开放许可证，就宣称整个项目已按同一许可证开放。后续由维护者明确授权范围。

### 组件清单

| 项目／范围 | 本仓库包含 | 本次查到的上游许可 | 尚待完成 |
| --- | --- | --- | --- |
| FX / steamac 1.9.4 | 启动调用和期望的哈希／路径；无应用包 | [v1.9.4 顶层 LICENSE](https://github.com/fxgl/steamac/blob/v1.9.4/LICENSE)：Apache-2.0 | 专用副本与发行版差异、打包的运行库及依赖需分别审查；顶层许可不是整个 `.app` 的授权清单。 |
| StonkGuy FEX | 兼容性条件；无 FEX 二进制或源码整包 | [eac-main-20261022 顶层 LICENSE](https://github.com/StonkGuy/FEX/blob/eac-main-20261022/LICENSE)：MIT | 精确源码提交、附加补丁、第三方子模块和构建来源仍需与实际哈希对应。 |
| Proton-JE / Wine 等 | 版本／哈希条件和 Steam 控制接口；无兼容工具包 | [Proton-JE 的 LICENSE](https://github.com/jegglest/proton-je/blob/proton-je-11.0-20261014-3/LICENSE)说明使用多种许可证；[LICENSE.proton](https://github.com/jegglest/proton-je/blob/proton-je-11.0-20261014-3/LICENSE.proton)仅覆盖其顶层内容 | 逐项收集 Wine、图形层及其他组件的 LICENSE / COPYING、修改与相应构建材料；不标记整个包只有一种许可。 |
| gvproxy / gvisor-tap-vsock | 本项目的启动 wrapper 和校验条件；无网络程序二进制 | [上游顶层 LICENSE](https://github.com/containers/gvisor-tap-vsock/blob/main/LICENSE)：Apache-2.0；本地源码许可文件与此类型一致 | 实际 EIM 补丁版本、来源提交、Go 依赖许可和构建方法尚未完成可复现核对。 |
| Steam、游戏与 Guest 磁盘 | 不包含 | 本项目不为这些内容提供授权 | 使用者自行获取；不把账号、游戏或个人 Guest 映像打进发布包。 |
| Python / Node.js / macOS 字体 | 不包含运行时或字体文件 | 由各自来源提供；本仓库不重新授权 | 当前仅给出官方安装入口和调用关系；未来若打包需另做完整依赖审查。 |

这些上游许可信息仅表示查看了指定文件。可变分支链接以后可能变化；实际出包时需锁定源码提交、材料和校验值，不以“最新版”代替审查。

### 终端图案与 UI 截图

现有 `launcher-20261026/assets/emblem-*.txt` 是从官方 HELLDIVERS 2 标志／骷髅参考转换出的终端图案。历史来源：

- [PlayStation 官方游戏页](https://www.playstation.com/en-us/games/helldivers-2/)。
- [官方 logo 参考](https://gmedia.playstation.com/is/image/SIEPDC/helldivers-2-logo-dark-01-en-29jan24?fmt=png-alpha&wid=1200)。
- [官方 skull 参考](https://gmedia.playstation.com/is/image/SIEPDC/helldivers-2-feature-icon-01-en-05dec23?fmt=png-alpha&wid=512)。

**已记录来源，但尚未确认这些衍生图案的独立再分发权限。** 署名和来源链接不能代替授权。官方原始图片未纳入本仓库。品牌与图案权利归各自权利人，项目不宣称得到官方认可。

本次仅为当前既有 UI 增加离线预览 PNG，继承同一图案的权限问题；不把截图单独声明为可自由再分发的素材库。图片生成方式与脱敏范围见[图片说明](docs/images/README.md)。启动器及既有图案文件未因本次文档工作而修改。后续需确认权限，或单独评审替换为已获授权的图案；不能先替换界面再把它说成原有截图。

### 后续发布需要的记录

对准备加入的每一项组件或素材，记录：作者与来源、精确版本／提交、补丁、文件校验值、适用许可及声明、构建／源码材料和审查状态。未完成审查的第三方二进制不进入仓库或 Release。许可证与素材未决项必须在出包前由维护者明确处理。

## English

Reviewed 2026-10-29. This inventory checks upstream license files and the current source/artwork list; it does not clear redistribution of a complete runtime bundle. No project-wide license was selected, and no third-party runtime binaries were added.

The linked FX 1.9.4 and gvisor-tap-vsock top-level files identify Apache-2.0. The linked FEX branch identifies MIT. These findings do not settle bundled dependencies, local patches or provenance of the exact executable hashes. Proton-JE’s notice explicitly describes multiple licenses; `LICENSE.proton` covers its top level, while component LICENSE/COPYING files require separate review. Steam, game content, Guest disks, language runtimes and font files are excluded.

The existing terminal emblems were derived from the linked official artwork. Their source is documented, but separate redistribution permission has not been confirmed. Attribution is not permission. This project claims no official endorsement. The new offline UI previews inherit that artwork issue; they are not advertised as freely reusable artwork. Original promotional images are not included, and the runtime UI/emblem files are unchanged.

Before bundling anything, maintainers need exact origins, revisions, patches, checksums, license/notice files, applicable build/source materials and an explicit review outcome. Open dependency licenses do not assign a license to this project. Outstanding artwork and source-license questions remain visible for the maintainer’s release decision.
