# Native App 分支安全集成报告

日期：2026-11-03 · 执行：DeepSeek Harness · 依据：HD2_GIT_WORKFLOW_POLICY_V2 v2.0.0 及 AGENTS.md 相关安全规则

## 1. 任务执行摘要

对 4 个「已完成但未合并 main」的功能分支执行安全集成。审计发现其中 3 个分支（localization-recovery → ux-v2 → fx-selection-v21）构成**单一线性依赖链**，fx-selection-v21 已包含前两者；performance-v2 为**独立并行分支**，与 fx-selection-v21 在 13 个文件上产生语义冲突。

结论：安全集成 fx-selection-v21（一次带入 3 个分支的成果）；performance-v2 因语义冲突**保留分支、不合并**，需后续人工/Codex 协调。

## 2. 初始 Git 状态

- main = `be301b2` = origin/main（同步，未被其他 Agent 更新）。
- 主仓库工作树：`feature/macos-native-app` @ `ed9d893`，含 **18 个未提交文件**（Codex 正在开发）。
- 目标分支 tip：performance-v2 `98d8a38`、ux-v2 `b787e9e`、fx-selection-v21 `fd35293`、localization-recovery `543739c`。
- 受保护：`legacy-script`（`f6dfb4c`）、`backup/*`、子模块 `native-app/CoreSnapshot` @ `f6dfb4c`。

## 3. 四个分支的审计结果

| 分支 | merge-base | 相对 main 的提交数 | 包含关系 | 未提交修改 | 活跃 worktree | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| localization-recovery-20261103 | ed9d893 | 2（c346f9a, 543739c） | ⊂ ux-v2、⊂ fx-selection | 无 | 是 | 已被 fx-selection 完全包含 |
| native-app-ux-v2 | ed9d893 | 5（+331e7f5, 2d80d1e, b787e9e） | ⊂ fx-selection | 无 | 是 | 已被 fx-selection 完全包含 |
| native-fx-selection-v21 | ed9d893 | 6（+fd35293） | 链条尖端 | 无 | 是 | **可安全集成**（与 main 仅 1 处 AGENTS.md 冲突） |
| native-app-performance-v2 | ed9d893 | 3（f5c337f, b76c4cb, 98d8a38） | 独立 | 无 | 是 | **不可安全集成**（与 fx-selection 13 处冲突） |

`git merge-base --is-ancestor` 确认：localization ⊂ ux ⊂ fx-selection。

## 4. 实际集成顺序

按实际依赖关系，仅需集成链尖端 fx-selection-v21（一次带入 localization + UX + FX selection 三个分支的全部提交）。无需要按建议的「FX→本地化→UX→性能」逐个合并，因为前三者已线性包含。

## 5. 已成功集成的分支

- `feature/native-fx-selection-v21`（`fd35293`），连带其祖先链：
  - `feature/native-localization-recovery-20261103`（`c346f9a`, `543739c`）
  - `feature/native-app-ux-v2`（`331e7f5`, `2d80d1e`, `b787e9e`）

共 3 个原始功能分支、6 个提交、56 个文件（+5470 / -682）。

## 6. 未能集成的分支

- `feature/native-app-performance-v2`（`f5c337f`, `b76c4cb`, `98d8a38`）

原因：与 fx-selection-v21 在 **13 个文件**上产生内容冲突，且为语义冲突（非简单文本冲突），包括：

- `native-app/Services/AppUpdateManager.swift`：fx-selection 仅做 2 行本地化微调；performance-v2 做 **+188/-27 的重写**（新增 `UpdateReleaseService.swift`、`Config/Updates.xcconfig`、更新检查/发布脚本等），属两套不同的更新系统实现。
- `native-app/Views/GamePerformanceView.swift`：两条链分别重写（fx-selection +35/-35；performance-v2 +99/-25），性能系统实现分歧。
- `native-app/Stores/AppState.swift`：状态管理分别新增（+101 vs +27）。
- `native-app/bridge/legacy_operations.py`、`native-app/bridge/native-locales.json`：桥接与本地化资源分别修改。
- `native-app/HD2FXNative.xcodeproj/project.pbxproj`：两套文件集分别加入工程。

此类「功能取舍不明确 / 业务逻辑冲突」按任务规则停止自动合并，保留原始分支。

## 7. 冲突及解决方式

集成 fx-selection-v21 与 main（`be301b2`）仅 **1 个文件**冲突：`AGENTS.md`（两处区域）。

- 区域 1（版本头）：main 为 v1.2.9（Git 工作流策略），fx-selection 为 v1.2.10（本地化/UX 授权）。解决：合并为 **v1.2.11**，Change 说明同时涵盖 Git 工作流策略与本地化恢复/UX v2.1 授权。
- 区域 2（策略块）：main 新增「Git workflow policy」块，fx-selection 新增「Localization/documentation policy」与「UX instruction」两块。三者互不重叠，**全部保留**。

未使用 `-X ours` / `-X theirs`，未丢弃任何一方实现。

## 8. Debug 构建结果

`./script/build_and_run.sh --xcode-only`：**BUILD SUCCEEDED**（0 error / 22 warning），产物 `native-app/build/Debug/HD2FXNative.app`（版本 0.1.0 build 1）。

## 9. 自动化测试结果（全部 PASS）

- 本地化：`check_localization.py` PASS（10 语言 × 400 键覆盖，0 错误）；`localization_checks.py` 8 用例 OK。
- 迁移：`migration_checks.py` 36 用例 OK。
- 协议/桥接：`bridge_checks.py` 27 用例 OK。
- 服务：30 service checks PASS；启动/GUI：17 PASS；凭据：17 Python + 25 Swift PASS。
- 性能推理：9 PASS；FX 选择：`FXSelectionChecks` 14 PASS；`safety_guard.py` PASS（写/进程/网络/钥匙串访问全部 denied）。
- `plutil -lint project.pbxproj` OK。

## 10. 安全检查结果

`check_release_secrets.py --tracked`：**PASS**（107 文件，findings=[]）。合并提交时 pre-commit 钩子亦返回 PASS（56 文件）。

## 11. main 合并情况

在隔离 worktree（`integration/native-app-completed-features-20261103`）完成集成，合并提交 `1374f3f`。随后对 main 执行 **fast-forward 合并**（main 的 be301b2 为集成提交的第一父，属安全快进）。

## 12. 远程推送情况

推送 `origin/main`（fast-forward，非 force push，未重写历史）。

## 13. Codex 工作区保护验证

- 未切换 Codex 正在使用的分支（`feature/macos-native-app`）。
- 未修改/重置/清理/stash/rebase Codex 工作区。
- Codex 的 18 个未提交文件全程保留、未被触碰（所有操作均在 DeepSeek 自建隔离 worktree 中完成）。
- 未修改 `legacy-script`、`backup/*`、子模块 `CoreSnapshot`（指针保持 `f6dfb4c`）。

## 14. 最终 Commit Hash

- 集成合并提交：`1374f3f`（`merge: integrate feature/native-fx-selection-v21 …`）。
- main 最终指向该提交（本报告为随后的 docs 提交）。

## 15. 未完成事项

- `feature/native-app-performance-v2` 未集成（13 文件语义冲突，需人工/Codex 协调「更新系统 + 性能系统 + 状态 + 本地化」四处的实现取舍）。
- 原始四个功能分支未删除（按授权保留，需后续单独确认）。
- FX 选择/本地化/UX 的**实机运行验证**（真实 FX/Guest/游戏）仍属 UNVERIFIED，本次仅完成编译与隔离 fixture 测试。
