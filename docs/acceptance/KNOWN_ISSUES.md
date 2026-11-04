# 已知问题与验收缺口

验收日期：2026-11-05（Asia/Shanghai）。源码基线 `8ba547c390d52971a7740a1970411c9e153c44b7`；验收分支 `audit/full-acceptance-20261105`。修复构建提交及 SHA-256 以候选目录的 SOURCE-COMMIT.txt / executable-sha256.txt 为准。基线 App 0.1.0 / 2026110411；修复构建 App 0.1.0 / 2026110501。未声称已发布 v1.0.0。

证据根：`native-app/evidence/`（本地忽略，交付时复制到候选 Evidence）。PASS 只适用于记录的范围；单元/隔离替身结果不代表真实 Guest 或游戏。未执行的真实项目一律 NOT TESTED，缺少前提的项目 BLOCKED。截图为真实 Debug App 窗口，非模拟 UI；抽查不代表全部交互已验收。

数量按“发布门禁问题及证据缺口”计，非已确认代码 bug 数：开放 P0=2、P1=5、P2=1；另已修复 P2=2。

| ID | 级别 | 问题 | 状态 | 证据/处理 |
|---|---|---|---|
| P0-01 | P0 | 正式分发缺 Developer ID、已验证公证/安装链与正式 DMG | OPEN | ad-hoc TeamIdentifier 未设置；这是发布阻断，不是凭据缺陷 |
| P0-02 | P0 | 完整一键启动、主菜单、单人/多人验收无本次真实证据 | OPEN / NOT TESTED | 核心发布验收缺口；不声称代码已证实损坏 |
| P1-01 | P1 | 首次部署审核 FEX/Proton 制品缺失 | BLOCKED | 维持 ARTIFACT_UNAPPROVED |
| P1-02 | P1 | FX 1.9.9 性能写入/部署 profile 不支持 | OPEN | 拒绝写入正确；须独立兼容开发与验证 |
| P1-03 | P1 | 真实 SSH/独立 sudo/Guest/IPv6/配置恢复未验收 | NOT TESTED | 等待 FX 启动及逐项授权 |
| P1-04 | P1 | 自动更新无生产签名包及隔离升级验收 | BLOCKED | 禁止把集成 Sparkle 当可升级 |
| P1-05 | P1 | 安全停止/重启 FX/VM 后端缺失 | OPEN | 不以强杀替代 |
| P2-01 | P2 | FX 扫描与选定提示重复候选 | FIXED / RETEST PASS | 保留失败和实际复测；63 Core checks |
| P2-02 | P2 | 双语文档仍要求原脚本目录/六页面 | FIXED | 改为内置资源/七页面，发布记录仍为开发预览 |
| P2-03 | P2 | 八语言视觉、完整 GUI 交互及稳定性覆盖不足 | NOT TESTED | 20窗口捕获和静态键检查不能替代 |

未验证没有强制映射为 FAIL：项目实际状态详见台账。公开分发前还需解决仓库统一源码许可/组件再分发来源审核；不得擅自选许可证或取得私钥。
