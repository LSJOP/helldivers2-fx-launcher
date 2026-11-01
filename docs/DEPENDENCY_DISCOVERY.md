# 已有依赖发现 / Existing dependency discovery

[安装流程 / Setup](SETUP.md) · [依赖清单 / Inventory](DEPENDENCIES.md) · [README](../README.md)

## 简体中文

**先定位已有文件，再决定是否需要安装。** 当前源码树的 FX/gvproxy 指定位置不存在，不能推断电脑没有安装。既有开发副本、`/Applications` 或其他用户选择的位置可能已有可用组件。检测不会重装、复制、移动、替换、修改权限或接管它们。

### 入口与路径语义

`[3] 安装环境检查 → [5] 定位已有依赖`：

```text
[1] Node.js
[2] FX
[3] gvproxy-eim
[4] 查看候选
[0] 返回
```

选择组件后可重新发现、输入／从 Finder 拖入一个路径，或查看候选详情。回车/0 取消手动输入。支持空格、中文、引号、Finder 转义、`.app` 和符号链接；相对路径以项目根目录为准。输入只当路径处理，不执行 Shell、变量展开或命令替换。

- **发现路径**：有限搜索或用户输入得到的候选，可能不存在／不可执行／不匹配。
- **验证路径**：实际只读检查的文件；符号链接解析后去重，别名不代表另一份组件。
- **运行路径**：从现有后端代码与当前进程环境读取的选择。检测结果不能修改这个选择。

页面对个人路径做脱敏，报告不包含任何候选路径。即使候选哈希匹配，启动仍使用原后端路径和全部原有依赖／实例／身份检查。**发现别处的组件不会解除主菜单受限模式，也不会让原启动流程自动使用它。**

### 有限自动发现范围

| 组件 | 候选来源 | 不做什么 |
| --- | --- | --- |
| Node | 后端当前规则、PATH 前32目录、Apple Silicon/Intel Homebrew 的 bin 与有限 versioned opt、官方常用 `/usr/local/bin/node`、`NVM_BIN`、可选 nvm current 链接、`FNM_MULTISHELL_PATH/bin/node`、Volta bin（仅发现） | 不调用 brew/nvm/fnm/volta，不 source profile，不运行已识别的管理器 shim，不扫描所有历史版本，不改 PATH |
| FX | manifest、后端 APP、`/Applications` 与 `~/Applications` 中浅层 FX/steamac 应用、项目父目录前16个 `HD2-*` 已知结构项目、手动路径 | 不全盘扫描、不启动应用；普通 FX 1.9.4 不自动等同于专用补丁版本 |
| gvproxy | manifest、后端 GVPROXY、上述相关项目的相同相对位置、手动路径 | 不搜索同名系统程序，不执行 binary/wrapper，不改网络或目标 |

每组件至多24个去重自动候选、8个手动候选；应用目录至多枚举64个 `.app`，每个 Homebrew opt 至多8个匹配项。已知／已存在路径优先；手动路径不因自动列表已满而被丢弃。限制会影响完整性，达到候选或探针预算时标为部分结果，不能宣称全机未安装。

nvm 的 `NVM_BIN` 是活动版本目录，`current` 链接只有用户原先启用该行为时才存在，检测不会创建它（[nvm 官方说明](https://github.com/nvm-sh/nvm#environment-variables)）。fnm 只读取已有 multishell 环境，不执行其环境初始化（[fnm 官方源码](https://github.com/Schniz/fnm/blob/master/src/commands/env.rs)）。没有这些环境或链接时，允许手动定位实际原生 Node；不会猜哪个历史版本当前有效。

### 只读校验与状态

Node：原生文件格式／架构、执行权限；仅原生 Node 本体通过参数执行已审阅的 `tools/check_node.cjs` 源码快照（先读入并验 SHA-256，不执行校验后可能被替换的文件），每次5秒超时，只判断版本 >=22 与全局 fetch/WebSocket，不建立连接。非原生、其他工具／管理器 shim、预加载／覆盖率／编译缓存环境或探针源码被改动时跳过执行，保留“已发现／未验证”。不触发 Rosetta 或软件安装。文件变动使缓存失效；每组件有总探针预算。

FX：目标 `Contents/MacOS/steamac-vm`、权限、SHA-256，同时比对 manifest 和后端期望值；若可读取则展示 Info.plist 的数值版本。manifest 没有权威版本要求时，**版本匹配保持未验证**，不凭“1.9.4”断言补丁兼容。

gvproxy：普通文件、权限、两处 hash 证据、同目录 wrapper 是否是已审阅源码并可执行。wrapper 检查只证明本机文件关系，不证明它正在运行、EIM/NAT/UDP 生效或联机成功。

| 状态 | 显示与含义 |
| --- | --- |
| 本机校验通过（绿） | 仅此处列出的校验通过，且与解释出的运行路径一致；实际运行仍未验证 |
| 已发现待验证（黄） | 存在文件／应用，但兼容性证据不足，或合格候选与实际运行路径不同 |
| 指定位置未找到（黄） | 该路径无文件；不是“未安装” |
| 版本／哈希不匹配（橙） | 有明确不匹配证据；不删除、不覆盖 |
| 当前不可执行（红） | 非普通文件、缺执行权限或链接循环；不自动修复 |
| Guest／探针未验证（灰） | 未读取 Guest、未知格式／环境、失败／超时等；不伪装成功 |

### 保存与报告

手动输入仅存当前安装中心会话，退出／重开后丢弃。不写 settings.json、manifest、后端常量、PATH 或用户配置，未知字段保持原样。

主动导出的安装报告增加去重候选数、实际发现数、各候选状态、来源类别、数值版本、版本／manifest hash／后端 hash／wrapper／运行路径一致性布尔证据和部分扫描标记。缺证据为 null，不强行转成失败。**不导出任何原始路径、文件摘要、错误字符串、用户名、私有 IP、密码或 Token。**

### 当前 M4 Pro 定位说明与限制

维护者只读核对发现：源码发布目录没有 FX/gvproxy 二进制，已知开发副本的对应文件存在且匹配清单哈希。这解释了之前的指定位置提示，不是新的游戏或联机验收。新检测会把符合上述有限范围的项目列为候选，但不切换实例。

仍找不到时：先确认当前打开的是哪个项目文件夹；在 Finder 找到原先实际使用的 FX `.app`／gvproxy 文件，拖入对应手动定位页；Node 可提供既有原生 `node` 文件。若只有 shim／未知版本，保留为未验证，不重装。超出范围、没有活动版本环境、权限、链接循环、hash 或 wrapper 不符，都在详情中分开显示。自动接管／持久化和完整一键安装未提供。

## English

**Locate existing files before considering installation.** Missing from a configured source-tree path does not mean a component is absent from the Mac.

Use **[3] → [5] Locate existing dependencies** for Node, FX, gvproxy and candidate details. Each component supports refresh and manually typed/Finder-dragged paths; Return/0 cancels. Paths are session-only data, never Shell commands. Relative paths use the project root; quoting, spaces, Chinese characters, apps and symlinks are supported.

Discovery, validation and runtime paths are separate. Backend constants and the current process environment identify runtime choices through a restricted AST reader; unrecognized rules stay unknown. **No discovery result changes runtime selection or bypasses existing launch checks/limited mode.**

Automatic scope is bounded: backend/manifest paths; first32 PATH entries; native/Intel Homebrew bin and limited versioned opt; common official `/usr/local/bin/node`; existing nvm active/current and fnm multishell paths; Volta shims are found but not run. FX searches up to64 shallow apps in each Applications folder and up to16 sibling `HD2-*` projects with the known backend structure. gvproxy searches only configured/related-project/manual paths. There is no recursive/full-disk scan or manager/profile initialization.

Up to24 automatic and8 manual candidates per component are deduplicated. Existing and runtime/manifest entries are prioritized; manual entries remain inspectable. Search/probe bounds can make results partial. No global absence claim is possible.

Only a recognized native Node payload may run the reviewed offline capability source snapshot (read once, SHA-256 checked, passed as an argument without Shell), with a5-second per-process timeout and component budget. Required version/globals are checked without opening URLs. Recognized shims, non-native/unknown files, preload/options/coverage/cache environments and modified probe source remain unverified; no PATH changes, downloads or Rosetta installation are triggered.

FX/gvproxy are never executed. Permissions and streaming hashes are compared separately with manifest and backend evidence. FX numeric bundle versions are informational; matching version text alone does not verify patched compatibility. gvproxy wrapper evidence requires the reviewed sibling script and permissions; it does not verify live EIM/NAT/UDP or multiplayer.

Green means stated local checks passed and the runtime path matches; yellow means found/unverified or a missing specified location; orange means explicit version/hash mismatch; red means currently non-executable; grey means pending/failed/unknown. Guest checks remain pending. A good candidate elsewhere never becomes the launch path automatically.

Manual paths are never persisted. Explicit reports contain only allowlisted counts, source categories, numeric versions, states and nullable evidence booleans, never paths/digests/errors/credentials/private IPs. Existing settings and unknown fields remain byte-identical. Sources and installation instructions remain in the [dependency inventory](DEPENDENCIES.md).

A read-only maintainer observation found matching FX/gvproxy files in an existing development copy while the sanitized release tree excludes them. This is file evidence, not a fresh-Mac or game/multiplayer test. If discovery misses your existing setup, use Finder to locate the exact app/native Node/network file and validate it manually; preserve unknown versions rather than reinstalling. Persistent path adoption and turnkey setup remain unavailable.
