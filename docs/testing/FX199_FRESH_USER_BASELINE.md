# FX 1.9.9 首次配置基线与验收

核对日期为 2026-11-27（Asia/Shanghai）。GitHub 稳定版基线为 v1.0.6，main 为 `c5e26e92072469da486ef9859e844597e0c7ad90`。开发验收使用 PR #23。四份参照资料为 [FX 1.9.9 新镜像报告](../environment/FEX_BASELINE_REPORT_20261115.md)、[FX 1.9.12 历史环境报告](../environment/FEX_SUCCESS_ENVIRONMENT_REPORT_FX1912_20261115.md) 和本地审计目录中的 `FX_PREVIOUS_OPERATIONS_AUDIT.md`、`STEAMOS_ENVIRONMENT_TRACE_20261104.zh-CN.md`。

## 三个环境

| 环境 | 结果 | 证据 |
| --- | --- | --- |
| FX 1.9.12 历史成功环境 | PASS（只读参考） | 本次采用既有历史报告。正式原盘留在原位。 |
| FX 1.9.9 `FX199_FRESH_USER_BASELINE` | BLOCKED | 当前可见完整镜像和离线备份均无法还原为首次配置前状态。外置 APFS 卷未找到快照。 |
| FX 1.9.9 工作测试环境 | BLOCKED（新用户验收） | FX 1.9.9 测试实例绑定原有独立工作镜像，SSH 配置端口 2223。离线检查显示已配置。 |

离线以只读文件句柄读取 GPT 与 ext4 Home 分区，无挂载和日志重放。已有 `FX199-RF-acceptance.ARpYR0/backup.img` 和 `test.img` 已包含受管理 RF、Steam FEX-Emu、Proton-JE 与 Runtime 4。备份的 Steam Runtime 4 Build ID 为 `26116036`，ARM64 Runtime Build ID 为 `26116077`，游戏 Build ID 为 `26568081`。备份中游戏可执行文件和原始 ARM64 Proton 的 SHA-256 与 11 月 15 日报告一致。工作盘的 ARM64 Proton 启动脚本已变化。11 月 15 日的未配置观测记录属于在线镜像观测，缺少可直接恢复的原盘快照。上述 Build ID 是既有镜像证据。

引入新母本之前，对照原始报告验证三个新增目标的缺失、原始 ARM64 组件、FEX 注册、Steam 映射和启动项、游戏、Steam 登录及操作前状态。保存镜像校验值、来源、FX 版本、Guest 身份指纹和备份日期。将母本设为只读。恢复时确认 FX 停止且工作盘未打开，从母本生成新工作副本并核对完整 SHA-256。FX 只绑定工作副本。使用独立启动器数据区域清除本轮首次配置记录。用正式 App 核对恢复前快照，再执行首页启动。每次测试前重复同一恢复过程。

备份 `backup.img` 的 144.29 GB 逻辑内容经 APFS 写时复制，生成独立 inode 的临时副本。源与副本完整 SHA-256 均为 `bdfe63971dccf533264a251f27938a69c3675cb43ba3f5c6d64f98ee8df62a02`。复制和完整性验证为 PASS。副本验证后清理，现有备份和工作盘均留在原位。干净母本恢复仍为 BLOCKED。

钉住的 Proton-JE 归档中 `toolmanifest.vdf` 要求 4183110，归档内部版本为 `1792806463 proton-je-11.0-20261014-3`。这与 Runtime 4 官方安装选用的 AppID 一致。

## 实机状态

| 项目 | 结果 |
| --- | --- |
| 恢复后全缺失和三种单独缺失 | BLOCKED |
| 内置 RF FEX、Proton-JE 自动部署与重启持久化 | NOT_TESTED |
| Runtime 4 官方安装、版本、Build ID、耗时与下载量 | NOT_TESTED |
| 损坏和权限修复、正确组件跳过、重复配置 | NOT_TESTED |
| Steam 未登录、断网、空间不足与取消恢复 | NOT_TESTED |
| 不同 Steam 库、保留 ARM64 环境、Mac 重启 | NOT_TESTED |
| 旧正式版真实增量升级及升级后配置 | NOT_TESTED |
| 首页点击到 Steam 请求、进程、窗口、主菜单、单人任务、正常退出及再次启动、EAC 和多人 | NOT_TESTED |

先完成可核验的母本恢复，再开始上述实机矩阵。保存源码 SHA、App 构建号、镜像指纹、各阶段日志和中英文真实截图。不得使用反作弊绕过。既有环境、隔离测试、签名或 Steam 启动请求均单独记录。
