# 真实用户首次配置 FX 运行环境故障分析

日期：2026-11-22（Asia/Shanghai）
分支：`fix/first-run-ssh-access`
基线：`c32ce24b9cfd90d197b21cc9cfda45ce3948c0a8`

## 截图能够确认的现象

用户截图显示 FX 检测成功、SteamOS SSH 连接成功，环境检查阶段停止，配置未完成，用户可见提示为旧文案“FEX 需要修复”，展开技术信息为 `FEX_MISSING`。截图不能证明具体文件、路径、权限、用户 ID 或资源来源，不能据此认定根因。

## 实际触发链

`FEXWorkflow.runtimeProbe` 先检查当前已认证 SSH 用户 HOME 下的 App 管理目录，再检查 Steam 默认目录。找不到可执行文件且 Proton 集成库不满足时返回 `FEX_MISSING`。`AppState.startEnvironmentWorkflow` 原先取得计划后直接抛出该阻塞码，没有调用已有的审核、部署、备份、验证与恢复事务。这解释了“SSH 已成功但没有继续自动修复”；它不证明远端权限一定正常。

候选将探针结果细分为组件不存在、目录存在但二进制缺失、目录/配置读取权限、执行权限、架构、注册配置、RootFS provider、树完整性和实际运行失败。外部兼容错误码保留，技术诊断增加 `diagnostic_reason`、实际来源类型和经脱敏的路径。

## ID、路径与权限排查

- 未发现个人 SteamID 白名单。`553850` 仅作为 HELLDIVERS 2 AppID。SteamID64 只从 `loginusers.vdf` 的唯一 MostRecent 账户推导当前 userdata 子目录；多个活跃身份停止并报告冲突。
- 游戏库从 `libraryfolders.vdf` 的实际根目录发现，不再只依赖 `$HOME/.local/share/Steam`。清单和游戏程序必须在同一发现库中存在。
- 生产代码不固定 UID/GID；远端 HOME、用户名和所有权由认证会话、`id -un`、`id -u` 与文件属性获得。SSH 连接成功不再等同于组件可读/可执行。
- 默认 SSH 用户仍可配置。主机密钥、目标身份、Guest boot、FX 路径和可执行哈希继续绑定；没有新增密钥自动选择或认证降级。
- Bundle Identifier 保持 `com.lsjop.helldivers2fx.native.phase1`，未迁移配置、凭据或更新身份。App 管理的 Guest 持久目录保持既有路径，避免覆盖 Steam depot。

## RF 资源与许可结论

当前 App Bundle 没有完整 RF 二进制组。`deployment-components-v1.json` 仅批准配置、补丁、许可文本和现有清单资源；历史 RF 文件均为 `bundled: false`，公开分发状态为 `BLOCKED_PUBLIC_RF_DISTRIBUTION`，备用下载源为 `UNVERIFIED`。

固定 FEX 源码根许可证为 MIT，但历史二进制、完整辅助文件、子模块/依赖通知、可复现构建及分发链尚未闭环。新的固定源码构建输出也未必匹配历史批准可执行哈希。因此候选不会把历史测试盘二进制塞进公开 App，也不会把“编译成功”当作可部署批准。

## 代码修复

- `FEX_MISSING` 及其他可修复状态自动进入修复阶段；若已有精确匹配且身份绑定的审核候选，则复用原事务安装并实际执行验证。
- Bundle/备用源没有批准 payload 时返回 `ARTIFACT_UNAVAILABLE` 和 `RF_BUNDLE_PAYLOAD_UNAVAILABLE`，保留重试及具体诊断，不再静默停在缺失检查。
- 用户界面十语言统一显示 FX；底层 `FEX_MISSING`、`FEX_ROOTFS`、`FEXBash`、路径和协议保持原样。
- 失败页新增复制诊断报告，包含版本、阶段、内部码、组件结果、修复尝试、来源和校验；自动脱敏 SteamID、用户名、个人路径、SSH 密钥路径及凭据。
- 新增构建门禁，检查十语言品牌、内部技术标识、个人路径/SteamID/UID/GID、Bundle ID 以及所有声明 Bundle 资源的大小和 SHA-256。

## 验证结果

| 项目 | 结果 | 限制 |
|---|---|---|
| 运行探针 fixture | PASS（15） | 非真实 Guest |
| RF 事务 fixture | PASS（21） | 非真实部署 |
| 部署核心 | PASS（161） | SSH/VM/游戏 NOT_TESTED |
| Native Core | PASS（107） | 含诊断脱敏 |
| 十语言 | PASS（625/625） | 真实 App 简中主窗口/环境/首次配置已复核；失败态仅 zh-CN/en fixture |
| arm64 Debug build | PASS | 非签名 Release |
| RF 缺失自动进入修复 | PASS（代码/静态门禁） | 实际资源部署 BLOCKED |
| FX 1.9.9 基线恢复 | NOT_TESTED | 批准 payload 缺失，未冒险写盘 |
| 两次正常重启 | NOT_TESTED | 同上 |
| 游戏进程/窗口/主菜单/单人/EAC/多人 | NOT_TESTED | 未启动游戏 |

## 未解决问题

P1 仍需一个许可、来源、完整依赖、构建版本和哈希均审核完成的完整 RF 包，并建立同身份的受信 HTTPS 备用源。随后才能安全恢复 FX 1.9.9 基线，使用真实 App 完成缺失、损坏、权限、下载失败、重复配置、两次重启和游戏矩阵。历史三份审计报告未修改；现有成功环境未写入。

只读恢复预检确认 `/Volumes/Thunderbolt2TB/steamos-1.img` 为 144286154752 字节、最后修改时间 2026-11-16 16:11:57 +0800，当前没有 FX/QEMU/游戏进程或 `lsof` 占用；完整 SHA-256 为 `bdfe63971dccf533264a251f27938a69c3675cb43ba3f5c6d64f98ee8df62a02`。现有基线报告明确说明其原始记录来自运行中镜像、不是离线备份；本轮搜索没有找到可确认对应当前 `steamos-1.img` 的完整备份。另两个大镜像身份不同且未被假定为备份。因此恢复安全前提不成立，未执行删除、覆盖或回滚。
