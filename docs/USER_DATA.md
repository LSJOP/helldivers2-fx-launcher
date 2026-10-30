# 用户数据与更新保护 / User data and update protection

[README](../README.md) · [在线更新](UPDATES.md) · [源码文件候选清单](update-managed-files.draft.json)

## 实际存储位置

以下来自 preferences.py、keychain_store.py、performance_profile.py、network_profile.py、network_records.py、network_diagnostics.py 与 launch_safety.py；不是假设所有数据都在项目目录。

| 内容 | 实际路径或机制 | 更新策略 |
| --- | --- | --- |
| SSH 参数、语言、图案、动画、布局 | `~/Library/Application Support/Helldivers2FXLauncher/settings.json`；可由 `HD2FX_SETTINGS_FILE` 改到任意位置 | 永不作为程序文件替换 |
| SSH 密码 | macOS Keychain service `org.hd2fx.launcher.ssh-password.v1`，account 由地址、端口、用户名散列生成 | 不读取、导出、重建或迁移密码；保持服务及引用标识 |
| SSH 私钥、known_hosts | 用户选择的私钥路径；OpenSSH 的 `~/.ssh/known_hosts` 或用户 SSH 配置指定位置 | 不属于更新器；不得复制凭据到公开日志 |
| 网络配置 | 与实际 settings.json 同目录的 `network-profile.json` | 保留整个文件及未知字段 |
| 成功快照 | 与实际 settings.json 同目录的 `network-snapshots/` | 保留全部历史及更新期间新增记录 |
| 诊断历史及导出 | `~/Library/Application Support/Helldivers2FXLauncher/Diagnostics/`，历史文件 `history.jsonl` | 不随 settings 路径覆盖而迁移；整个目录保护 |
| 环境报告 | 项目内 `launcher-20261026/reports/` | 不替换、不上传 |
| 性能和 Guest 变更私有备份 | 项目内 `launcher-20261026/backups/` | 不替换、不删除 |
| 实际 FX 性能设置 | macOS UserDefaults domain `es.fxgam.steamac`，系统管理的 `~/Library/Preferences/es.fxgam.steamac.plist` | 更新器不调用 defaults、不写 plist；保留用户实际值 |
| 官方性能预设 | `performance_profile.py` 的原参数与 `performance_catalog.py` 的范围、状态元数据 | 属于候选程序源码；没有可信安装基线时不能覆盖 |
| 用户选择／自定义预设 | 当前没有独立持久化预设选择／编辑器；用户可能直接修改脚本或在任意位置保存自定义数据 | 不虚构固定路径；未知路径不在白名单；已改脚本拒绝替换 |
| 外部代理配置 | 诊断可只读观察 FlClash 的 `~/Library/Preferences/com.follow.clash.plist`；其他代理存储不由本项目管理 | 永不更新或重置 |
| Guest Steam／启动参数／IPv6 | Guest 内部，由启动链路的独立确认和恢复机制管理 | 在线更新不连接 SSH，不触碰 Guest |
| FX、FEX、Proton、gvproxy-eim、Steam、游戏文件 | 外部组件／Guest／用户选择的安装位置 | 永不进入启动器更新白名单 |

## 当前已经实现的保护

当前只有主动版本查询、日志展示和打开官方 Releases。**没有下载、文件替换、安装工作进程、配置迁移或自动回滚执行器。实际更新文件清单为空。** 网络错误、中断、异常资源不会触发配置写入。

`update_protection.py` 提供只读存储位置清单、严格相对路径检查、受保护路径拒绝、候选清单检查、文件 SHA-256／权限指纹，以及本地修改冲突检查。缺少可信的已安装版本原件基线时显示归属未知。即使候选文件散列相符，返回的 `install_allowed` 仍为 false。不会现场将用户文件散列当成官方原件。

该模块不访问 Keychain，不执行 Git 命令，不自动修复冲突。遇到冲突应取消安装，保留目录，手动比较个人修改和官方源码；不要使用强制覆盖、git reset 或 git clean。

`merge_defaults` 是供未来显式迁移使用的纯函数：只补缺少字段，保留已有值及未知字段，遇到嵌套类型冲突报错；不落盘。目前没有启用迁移。现有普通设置验证器仍按已知 schema 筛选字段，因此不能将它用作未来无损迁移工具；安装功能开放前必须专门验证兼容性。

## 安装开放前必须完成，当前不能宣称已实现

- 精确白名单及受信的当前／目标版本 manifest；未知文件及用户新增文件永不覆盖。当前 JSON 是设计草案，不是签名清单。
- 安装前在私有本地目录备份 VERSION、将替换的源码、用户配置快照及必要元数据。保留原文件权限；备份目录至少 0700，含凭据资料不得上传、写公开日志。Keychain 只保留引用元数据，不导出密码或系统钥匙串数据库。
- 配置迁移与源码更新分开：确认、备份、明确迁移函数、新 schema 验证；失败恢复旧文件，不丢未知字段。官方预设可更新，已选预设和自定义参数不得替换，不兼容时提示。
- 独立更新程序等待所有启动器入口退出，事务记录每次替换。失败恢复本次修改的程序文件和 VERSION；回滚前再检查现值，遇到用户新增／改变的数据停止并提示手动处理，不删除它们。
- 逐项验证语言、外观、SSH 参数、Keychain 引用、性能、网络和历史保持一致，并用隔离 HOME 的入口冒烟测试验证新 UI；不得以启动游戏作为验证。
- 故障注入需覆盖下载、校验、替换、断电／中断、恢复失败、权限、中文空格路径和并发文件修改。磁盘故障等不能保证自动恢复，应保留私有备份并给出手工路径。

当前 Mock 测试证明只读检查不修改测试配置、能拒绝危险候选及本地修改；**不是已完成安装、配置迁移或回滚的证明**。安装继续禁用，优先保证现有数据。

## English

The table inventories real storage, including Application Support, a settings-file override, Keychain, SSH-selected key paths, macOS UserDefaults, project-local backups/reports and Guest data. Custom preset persistence has not been implemented; arbitrary user files remain outside the managed-file allowlist.

The current update system only checks versions, displays notes and opens Releases. Its actual replacement list is empty. No installer, migration or rollback worker exists. Read-only preflight rejects protected/unmanaged paths, symlinks, unknown ownership and locally edited files; matching hashes cannot unlock installation. It never exports Keychain credentials or runs Git commands.

The pure default-merging helper preserves existing and unknown values without saving anything. Existing normal settings validation filters known fields and must not be reused as a lossless migration. Future migrations need separate confirmation, private backups, schema verification and cautious rollback. Code updates must preserve configuration, selected/custom presets, network state and every historical/new record. Keychain service/account references must remain stable without exporting passwords.

Before installation can be enabled, a trusted installed-file baseline, exact manifest, private permission-preserving backups, independent worker, durable transaction log, conflict-aware rollback and post-update configuration checks must be implemented and fault-tested. Disk failures cannot guarantee recovery. Current Mock tests demonstrate read-only preservation and rejection, not successful installation or rollback.

## 安装引导与报告 / Setup guide and reports

安装引导不保存完成标记，也不通过 preferences.save 重写 settings.json。设置中未知字段不受影响。只读检查仅验证 SSH 设置结构，不读取密码或 Keychain，不复制现有网络或诊断记录。主动导出的新报告位于实际设置路径同目录 `reports/installation/`，0600，默认目录新建时 0700；不覆盖旧报告。不会进入 Git 发布内容。

The stateless setup guide never saves completion flags or reserializes settings. Unknown fields remain unchanged. Explicit report export creates a new 0600 allowlisted JSON in `reports/installation/` alongside the actual settings file; a new leaf directory uses 0700. It excludes credentials, user paths, raw configuration/history and is not release content.
