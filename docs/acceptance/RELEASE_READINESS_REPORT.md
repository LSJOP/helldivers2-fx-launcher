# Release readiness

验收日期：2026-11-05（Asia/Shanghai）。源码基线 `8ba547c390d52971a7740a1970411c9e153c44b7`；验收分支 `audit/full-acceptance-20261105`。修复构建提交及 SHA-256 以候选目录的 SOURCE-COMMIT.txt / executable-sha256.txt 为准。基线 App 0.1.0 / 2026110411；修复构建 App 0.1.0 / 2026110501。未声称已发布 v1.0.0。

证据根：`native-app/evidence/`（本地忽略，交付时复制到候选 Evidence）。PASS 只适用于记录的范围；单元/隔离替身结果不代表真实 Guest 或游戏。未执行的真实项目一律 NOT TESTED，缺少前提的项目 BLOCKED。截图为真实 Debug App 窗口，非模拟 UI；抽查不代表全部交互已验收。

**NOT READY**。不是 v1.0.0 正式 RC 放行；本地工程候选用于后续验收。

PR #3 已 MERGED（2026-11-04 UTC；合并 7bd7aed）。当前任务未合并 main、未推送、未发布 GitHub Release、未覆盖 Latest。基线版本0.1.0，修复仅更新 Build Number 为2026110501，保留真实产品状态。

基线候选：`/Volumes/Thunderbolt2TB/HD2-App-Builds/Candidates/acceptance-20261105-8ba547c/Products/HD2FXNative.app`。该构建不包含本次去重修复，勿作为修复版交付。

修复候选计划：`/Volumes/Thunderbolt2TB/HD2-App-Builds/Candidates/acceptance-fixed-20261105/Products/HD2FXNative.app`。仅在干净已提交源码构建并通过资源门禁后标记构建 PASS；实际 Commit/Build/SHA-256 记录在该目录。

正式 Developer ID、Hardened Runtime 分发评估、公证、DMG 安装、签名更新、完整真实游戏和新用户部署均未放行。8秒 Release 进程存活不证明全部窗口和功能；历史 Release/Sparkle 启动限制不直接沿用为本次已复现崩溃。
