# RF 资源内置与部署验收

开发分支基线为 `79095bf9819bc1321d31963585574b02a39d8d15`。历史镜像和审计报告保留原样。

| 范围 | 复用与变更 |
| --- | --- |
| 资源输入 | 12 个历史 stage 文件、28 个伴随文件和 1 个脱敏 wrapper。详见[逐项清单](../../native-app/Resources/rf-fex-debug-manifest-v1.json)。 |
| 构建 | 复用 Xcode 资源复制阶段，增加本机显式开关及复制前后核验。CI 和 Release 拒绝私有 payload。 |
| 首次配置 | 复用 `first_run_fex_repair`、身份绑定的 SSH/SFTP、持久化目录、事务收据、回滚及运行探针。已有 Debug 外部回放继续作为开发工具。 |
| Runtime 与 Proton | 复用 Runtime 4 已固定的 Valve 下载、缓存及验证，以及后续 Proton-JE 配置。保留 SteamLinuxRuntime_4-arm64。 |
| 分发 | Release Bundle 审批哈希清单当前为空。公开 RF 下载 URL 与制品哈希尚无批准记录。 |

在仓库根目录执行本地导入。将 `$RF_EVIDENCE_DIR` 指向已审核的历史证据目录。

```sh
python3 -I -B native-app/script/rf_fex_bundle.py import \
  --manifest native-app/Resources/rf-fex-debug-manifest-v1.json \
  --source-root "$RF_EVIDENCE_DIR" \
  --destination native-app/PrivateResources/Deployment/RF-FEX
```

使用独立构建输出目录，以 Xcode arm64 Debug 配置和 `HD2_PRIVATE_RF_DEBUG=YES HD2_UPDATE_ENABLED=NO HD2_UPDATE_DISTRIBUTION_READY=NO` 构建。App 运行时从 `Contents/Resources/Deployment/RF-FEX` 读取，并验证编译时固定的清单哈希。带私有资源的 App 仅本机使用。

历史 wrapper 从 6,536 字节转为 6,498 字节，移除环境打印。脱敏后 SHA-256 为 `e65da61350150ca527da3da9da5e5ecc1bf97ac9807d2e6ac22a09ffcf6f2045`。保留 ARM64 stock GDB reader。重复的 ThunksDB 使用同哈希的伴随资源副本。运行生成的 Python 缓存以及 stage 专用 GDB reader 均排除。

完整 Bundle 的 41 条文件路径、大小、模式和 SHA-256 见逐项清单。实际 Debug Bundle 目录的校验指纹为 `0ddd70d9b19e0a6abac26d9edb442fe43557376670c46d9489890f7eef913cd7`。部署保持空字符串 RootFS 注册，并由现有探针验证实际运行。

FEX 基础源码有 MIT 许可证记录。历史二进制的完整源码与补丁映射，以及 stock/Valve wrapper 和伴随库的再分发依据仍待确认。待审批项见环境组件清单。

| 项目 | 结果 |
| --- | --- |
| arm64 Debug Bundle 和 41 文件检验 | PASS |
| 真实 App 冷启动与打开首次配置页 | PASS，独立本机 App 数据目录 |
| 私有 payload 在 Release 和 CI 的构建拒绝 | PASS，执行 Xcode 资源阶段的两个负例 |
| 缺失自动进入修复入口 | PASS，静态检查 |
| 损坏替换、权限位、事务和 RootFS | PASS，隔离文件系统测试 |
| 真实 SSH/SFTP、App 配置 A–H、两次重启 | NOT_TESTED |
| Steam 启动请求、游戏进程、游戏窗口、主菜单、单人、多人 | NOT_TESTED |
| Release 制品与 RF 网络备用 | BLOCKED，等待制品及完整再分发审核 |

实际构建使用干净源码 `933872929de7019b88213f573854490dfc8a9009`。arm64 主可执行文件 SHA-256 为 `b057806cea25297fa44b2004178267b81de2bb8d0dd094d5cb4543973c5319be`，Debug dylib 为 `3610ffd1b9db423a33a50fc974b9784910f0a4802263a5197bc6111610182003`。实际 Bundle 的两项更新标记均为 `NO`。

资源树与清单共 42 个文件通过敏感信息扫描。新增及修改的 Git 文件也通过暂存扫描。全仓已跟踪文件扫描在既有 `PersistentCredentialChecks.swift` 中报告一项测试凭据模式命中，该文件本次无改动。
