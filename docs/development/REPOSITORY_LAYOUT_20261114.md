# 仓库结构整理 · 2026-11-14

## 范围

14 份根目录历史报告使用 git mv 移至 development（6）、architecture（4）、testing（4）。保留全部技术资料。现有 docs 分类保持原位。THIRD_PARTY_NOTICES.md 是法律说明，保留根目录；源码、发布脚本、updates 和固定子模块不移动。未创建空目录、LICENSE 或不存在的 GitHub Actions。

## 文件映射

- `CODEX_NATIVE_APP_TAKEOVER_REPORT.md` → `docs/development/CODEX_NATIVE_APP_TAKEOVER_REPORT.md`
- `FULL_SWIFT_NATIVE_REGRESSION_REPAIR_REPORT.md` → `docs/development/FULL_SWIFT_NATIVE_REGRESSION_REPAIR_REPORT.md`
- `FX_INSTANCE_MISMATCH_REPAIR_REPORT.md` → `docs/development/FX_INSTANCE_MISMATCH_REPAIR_REPORT.md`
- `HD2FX_NATIVE_UI_REFINEMENT_REPORT.md` → `docs/development/HD2FX_NATIVE_UI_REFINEMENT_REPORT.md`
- `NATIVE_FIRST_RUN_DEPLOYMENT_IMPLEMENTATION.md` → `docs/development/NATIVE_FIRST_RUN_DEPLOYMENT_IMPLEMENTATION.md`
- `NATIVE_FIRST_RUN_MAIN_MERGE_REPORT.md` → `docs/development/NATIVE_FIRST_RUN_MAIN_MERGE_REPORT.md`
- `FULL_SWIFT_NATIVE_MIGRATION_REPORT.md` → `docs/architecture/FULL_SWIFT_NATIVE_MIGRATION_REPORT.md`
- `HD2FX_MEMORY_ONLY_CREDENTIALS_CONSOLIDATION_REPORT.md` → `docs/architecture/HD2FX_MEMORY_ONLY_CREDENTIALS_CONSOLIDATION_REPORT.md`
- `NATIVE_ENVIRONMENT_PROFILE_MATRIX.md` → `docs/architecture/NATIVE_ENVIRONMENT_PROFILE_MATRIX.md`
- `STEAMOS_NETWORK_MANAGEMENT_MIGRATION_REPORT.md` → `docs/architecture/STEAMOS_NETWORK_MANAGEMENT_MIGRATION_REPORT.md`
- `NATIVE_DEPLOYMENT_SECURITY_REVIEW.md` → `docs/testing/NATIVE_DEPLOYMENT_SECURITY_REVIEW.md`
- `NATIVE_DEPLOYMENT_TEST_RESULTS.md` → `docs/testing/NATIVE_DEPLOYMENT_TEST_RESULTS.md`
- `NATIVE_FIRST_RUN_ACCEPTANCE.md` → `docs/testing/NATIVE_FIRST_RUN_ACCEPTANCE.md`
- `NATIVE_SUDO_CANDIDATE_VALIDATION_REPORT.md` → `docs/testing/NATIVE_SUDO_CANDIDATE_VALIDATION_REPORT.md`

## 冗余检查

删除 0 文件。未跟踪的本地构建缓存和旧脚本目录不属于此次 GitHub 清理范围，未操作。未发现可安全删除的已跟踪构建缓存。截图保留语言对应关系，见下方内容重复检查；相同字节不代表可删除，可能承担不同引用用途。

- 内容完全相同：`docs/assets/app-icon.png`, `native-app/Assets.xcassets/AppIcon.appiconset/icon-256.png`

## 分支快照

以 fetch 后 origin/main 为基准。已合并历史分支仅建议在确认无工作树、PR 或自动化依赖后另行清理。legacy-script 是固定子模块来源，长期保留；所有未合并分支保留，未删除本地或远程分支。

| 分支 | 状态 |
| --- | --- |
| `chore/repository-layout-20261114` | 已包含于 main |
| `development` | 未合并，保留 |
| `docs/auto-merge-policy-20261114` | 已包含于 main |
| `docs/v1-release-preparation-20261113` | 未合并，保留 |
| `docs/v1-release-readme-sync` | 已包含于 main |
| `feature/localized-app-brand-20261114` | 未合并，保留 |
| `feature/native-recovery-20261112` | 未合并，保留 |
| `main` | 已包含于 main |
| `release/v1.0.0-integration` | 未合并，保留 |
| `origin` | 已包含于 main |
| `origin/docs/auto-merge-policy-20261114` | 已包含于 main |
| `origin/docs/readme-changelog-policy-v1` | 已包含于 main |
| `origin/docs/v1-release-preparation-20261113` | 未合并，保留 |
| `origin/docs/v1-release-readme-sync` | 已包含于 main |
| `origin/feature/full-swift-native-migration` | 已包含于 main |
| `origin/feature/local-encrypted-credentials-20261105` | 已包含于 main |
| `origin/feature/macos-native-app` | 已包含于 main |
| `origin/feature/native-app-performance-v2` | 已包含于 main |
| `origin/feature/native-app-ux-v2` | 已包含于 main |
| `origin/feature/native-first-run-20261104` | 已包含于 main |
| `origin/feature/native-fx-selection-v21` | 已包含于 main |
| `origin/feature/native-localization-recovery-20261103` | 已包含于 main |
| `origin/feature/native-recovery-20261112` | 未合并，保留 |
| `origin/feature/proton-je-auto-install-20261106` | 已包含于 main |
| `origin/fix/native-launch-resources-20261103` | 已包含于 main |
| `origin/fix/steam-live-api-20261106` | 已包含于 main |
| `origin/fix/steamos-setup-steam-running-20261106` | 已包含于 main |
| `origin/integration/native-main-20261103-v2` | 已包含于 main |
| `origin/legacy-script` | 未合并，保留 |
| `origin/main` | 已包含于 main |
| `origin/release/v1.0.0-integration` | 未合并，保留 |
| `origin/ui/remove-global-fx-bar-20261104` | 已包含于 main |

## 验证结果

- 文档检查 15/15；双语 README、索引和移动报告的本地链接有效，14 个截图引用的语言目录、来源及哈希通过。界面与截图内容未修改。
- `native-app/script/build_and_run.sh --build-only`：arm64 Xcode Debug build 通过。
- `native-app/script/run_checks.sh`：完整通过，覆盖本地化正反例、FEX、更新资源、Proton、SSH、权限、网络、Native Core、FX 身份、启动、凭据、性能、选择和部署恢复隔离测试（部署检查 140 项）。首次遇到迁盘前旧 ModuleCache 路径，保留缓存后重跑通过；无产品代码修改。
- 源码、旧 Python、十语言资源、构建配置、发布脚本、updates 和 CoreSnapshot 指针均无差异。未执行真实 Guest/游戏/网络写入，未新增真实环境兼容性承诺。
- 当前 main 无 GitHub Actions 工作流，发布模板保持非激活；更新资源测试通过。远程 main 规则查询返回空规则列表。
- 引用更新限于双语 README、`.codex/progress.md`、系统验收报告和四份迁移报告；已跟踪文本无遗留裸旧路径。
- 其他工作树存在未提交成果，全部原样保留。未删除分支。提交前密钥扫描通过。
