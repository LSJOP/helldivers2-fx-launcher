# 阶段 B：安全安装更新设计 / Stage B installation design

[更新中心](UPDATES.md) · [配置存储清单](USER_DATA.md) · [文件候选清单](update-managed-files.draft.json)

> [!IMPORTANT]
> 本文件是供审核的设计，不是已实现的安装器。目前 `INSTALL_ENABLED = False`，实际替换文件为空。不存在可信包/归属基线、独立替换执行器、完整备份迁移和回滚证明，故不能开放安装。测试中的合成数据不建立真实发布信任。

## 1. 信任与发布协议

阶段 A 的附件解析只是展示级筛选；不能用它直接授权下载执行。安装协议还必须将以下信息绑定为同一受验证对象：

1. 固定官方 `LSJOP/helldivers2-fx-launcher`，经正常 TLS 的官方 Releases/asset 元数据；已发布而非 draft 的 Release ID、完整 SemVer tag、通道和资产归属。
2. Asset ID、明确安装格式/用途、精确名称、字节大小和 SHA-256；在单资产 API 中重新核实它仍属于选定 Release，没有选中同名其他资产。
3. manifest 的目标版本与包内 VERSION/Release 一致，平台明确为支持的 macOS Apple Silicon（darwin/arm64），包含最低系统/Python/配置格式要求和更新协议版本。真实系统不满足或无法可靠判断则停止。
4. 包 SHA-256 由可信官方 API `digest` 独立锚定，或由固定维护者/工作流身份验证的签名或证明锚定；受管理 manifest 本身也必须被同一可信包/签名绑定。不能只比对下载源旁未认证的 SHA256SUMS，不能因名称含 macOS 或哈希格式正确而判断可信。
5. 当前已安装版本还必须有可信的原件 manifest。main ZIP、未知 git 来源、本地现算的散列均不能被“认领”为官方基线。没有基线、脏工作区或脚本本地修改时展示冲突、取消并指导手工比较，不自动清理。

GitHub 资产字段见[官方 API](https://docs.github.com/en/rest/releases/assets#get-a-release-asset)。GitHub 的源码 ZIP/tarball 不是安装协议资产。当前没有选定或下载任何安装包，也没有假造 Release ID、签名密钥、兼容版本和下载地址。

## 2. 白名单与受保护数据

复用 [逐文件候选清单](update-managed-files.draft.json)，未来逐发布审核精确相对路径、原/目标哈希与权限。该草案不是实际可安装 manifest；没有目录通配或自动包含新增文件。

保护范围按 [USER_DATA.md](USER_DATA.md) 的实际路径处理，包括 Application Support、`HD2FX_SETTINGS_FILE` 任意覆盖路径、旁侧网络配置/快照、固定 Diagnostics、UserDefaults、Keychain、用户选定私钥、项目 backups/reports、任意自定义预设/脚本和 Guest 数据。官方预设源码只有归属证明完整时才可更新；用户选择与自定义参数不随之重置。不兼容旧选择应提示，不能代选其他预设。

包中出现 settings、凭据、网络/历史/备份或外部运行组件等受保护路径，**拒绝整个包**，不是跳过后继续安装。未知路径、额外文件、绝对路径、路径穿越、NUL/控制符、大小写/Unicode 冲突、重复条目、链接/硬链接/设备文件均拒绝。压缩/解压大小、数量、条目大小需有显式上限并做边界测试。目标路径每一级也必须拒绝符号链接/竞态逃逸；只对经过归属校验的普通文件操作。

## 3. 预检、下载、磁盘与备份

预检安装根目录真实路径、所有者、权限、当前/目标版本、文件归属和本地修改。ZIP/clone/移动/中文/空格路径使用同一规则，不运行 git pull/reset/clean。

下载只到私有临时目录，检查可信资产大小和哈希、完整 manifest、包内版本及平台；不执行包内安装脚本。官方资产下载可能重定向，未来须单独实现严格受控的 HTTPS 下载跳转策略，限定官方来源/资产及最终可信哈希，不复用当前拒绝所有 API 跳转的检查器来盲目下载。

核算暂存、压缩包、解压、原文件备份、事务元数据和安全余量所需空间，分别检查相关文件系统；空间/权限不可确认时不替换。当前安装路径不受支持或任何文件身份变化则停止。

替换前备份 VERSION、即将替换的受控文件、已知用户配置快照和必要元数据。备份目录 0700，记录原文件身份/哈希/权限；普通文件副本保留原权限，目录隔离访问，含凭据内容不上传、不写公开日志。配置快照同样留在私有目录；Keychain 只保留服务/账户引用元数据，不导出密码或整个钥匙串；不复制 SSH 私钥。拒绝异常所有者/特殊权限，不能默默改权限后假称原样保留。

备份完成后再次检查归属、哈希、空间和并发改动；验证私有副本可读且哈希一致。未完成可验证备份不能开始替换。

## 4. 独立更新程序与事务

预期流程：下载校验 → 预检/备份 → 用户确认精确版本、清单和配置影响 → 正常退出启动器 → 独立 worker 替换 → 隔离验证 → 必要时回滚 → 提示重新打开 Start.command。

worker 必须来自当前受信的已安装代码，先复制到独立私有目录并校验；不运行下载包内 worker/脚本，不替换它自身正在执行的文件。当前尚无此 worker。

所有启动器入口按同一真实项目根目录共享生命周期锁；交接验证父进程身份/所有者和一次性凭据，等待全部入口退出，不能只凭 PID 存在或设置目录锁猜测。不能终止 FX、Steam、游戏或其他启动器来获取锁。

替换采用同文件系统暂存、逐文件原子 rename、受控权限和持久事务日志/fsync。多个文件不是整体原子事务；每个状态均需有可恢复记录。中断后应由受信 bootstrap/worker 在加载可能不一致的新模块之前处理日志。未知事务/身份冲突不自动修复。

新版本验证只在隔离 HOME/设置路径、禁止网络/Keychain/原生配置写入的环境验证 VERSION、模块和 UI 渲染。未来需要专门实现无副作用的 smoke-check 入口；不能直接调用可能启动游戏的入口，也不能把当前尚无此入口写成已实现。验证成功仅提示重开 Start.command，不自动启动游戏或新程序。

## 5. 配置兼容与单独迁移

**代码更新不写用户配置。** 不调用旧 `preferences.validate/load/save` 组合来迁移：旧验证器会筛选已知字段。当前 `merge_defaults` 仅在内存补字段，保留值/未知字段；它不是完整 schema 校验器，也不是迁移事务。

新版本需先证明可直接读取旧格式。真的需要迁移时，独立展示影响并确认，原始 JSON 无损加载，专用版本迁移函数、私有备份、完整新 schema 校验、比较原文件身份后原子保存；不删除未知字段，不默默修正无效字段。缺字段可补合理默认值，用户已有值优先；类型冲突需停止并解释。

测试必须分别覆盖旧格式、新字段、缺字段、未知字段、无效字段、迁移中断、旧/新程序读取及回滚后兼容。迁移失败恢复自己的原写入前先检查现值；用户已新增/改动的数据不覆盖或删除。配置事务与代码事务分开记录，不能用回滚整个项目替代配置恢复。

## 6. 回滚与故障注入门槛

| 故障 | 将来必须证明的结果 | 当前证明范围 |
| --- | --- | --- |
| 下载中断/文件损坏/哈希错误/版本平台不符 | 没有进入替换；原文件、VERSION、配置不变 | 无下载器；只读元数据/禁用入口已测试，未测试真实下载事务 |
| 空间不足/权限不足/备份失败 | 替换前取消；保留可用原安装和配置 | 无空间/备份执行器，未验收 |
| 第 N 项替换中断/进程退出/断电日志 | 恢复本次修改的受控文件、权限和 VERSION；中断日志可重复恢复 | 无替换/恢复 worker，未验收 |
| 新版本模块/UI 无法启动 | 隔离验证失败，恢复原受控源码及版本；不触发游戏 | 无更新后 smoke-check/回滚，未验收 |
| 迁移失败/迁移中断 | 原配置无损；源码与配置的兼容策略明确 | 仅测试纯函数保值、类型冲突与不落盘，未实现迁移事务 |
| 回滚时用户新增数据/并发改动 | 比较后停止冲突项，保留新增/修改，报告手动路径 | 只读冲突/中断不写入已测；实际回滚未验收 |
| 恢复写入失败/磁盘损坏 | 保留私有备份、明确手动恢复路径，不继续破坏 | 不能保证硬件故障下自动恢复，未验收 |

worker 只能恢复日志中本次修改的受控路径，按原/目标哈希与身份比较后执行；不删除未知文件，不将旧目录整体覆盖。回滚原本不触碰的配置也不应被写回旧快照，否则会丢失更新期间的新数据。没有任何 killall/pkill 或系统网络变更。

## 7. 安装开放门禁

可信发布协议与资产、可信当前安装基线、完整 manifest、平台/版本/权限/空间校验、私有备份、独立锁/交接/worker、持久日志、配置兼容/单独迁移、隔离 UI 验证及上述所有失败点测试，均通过后才允许实现人工审核的启用改动。

本轮只完成阶段 A 和阶段 B 设计/只读拒绝契约验证。**未实现阶段 B 执行器，也未证明安装或回滚成功，安装继续关闭。** 真实设备安装还需单独验收，不能把临时目录测试叫作真实安装成功。

## English

This is a design, not an installer. Installation remains disabled. Official repository/Release/asset identity, exact version/platform/schema, trusted API digest or verified publisher proof, a bound exact manifest and a trusted installed-file baseline must all agree. Filename/hash syntax alone and source ZIPs cannot authorize installation.

Unknown/local-edited/user-data/runtime-component paths block the whole package. Archive/target path, link, Unicode/case, size/count, ownership, permission and disk-space checks are mandatory. Private permission-preserving backups include VERSION, replaced sources, known config snapshots and metadata, never exported Keychain passwords or private keys.

A worker from trusted installed code must run separately, wait for all launcher entries to exit using canonical-root locks, use durable per-file transactions and verify the new UI in isolation. It cannot stop FX/Steam/games or execute downloaded installers. Code updates do not migrate settings. Explicit migrations must preserve raw unknown fields and existing values, validate schemas and restore only their own writes after checking conflicts. The old filtering settings parser is unsuitable.

Download/corruption/hash, disk/permission, every replacement interruption, new-version failure, migration failure and concurrent-user-write rollback scenarios remain required before enabling installation. Current tests cover read-only refusal/preservation and pure merging, not download/replacement/backup/migration/rollback transactions. No true-device installation acceptance is claimed.
