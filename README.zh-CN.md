# HELLDIVERS 2 FX Launcher — Native App

[English](README.md) | [简体中文](README.zh-CN.md)

基于 **SwiftUI + AppKit** 的非官方 macOS 战术终端，通过受监管的 JSONL Bridge 复用原 Python Core。当前为**功能迁移开发预览版**，并非官方产品。

## 当前状态与功能

以下对应 `feature/macos-native-app`；`main` 可能仍是较早的只读预览。各功能迁移状态见[功能清单](docs/FUNCTION_MIGRATION.md)。

- 五个战术页面，原生导航/刷新快捷键，默认深色。
- 真实本机元数据、限定范围 FX 版本与发现路径；主动执行详细运行环境检查。
- 原启动流程、SSH/Guest/Steam 检查、性能配置、本机网络测试、网络方案及恢复均有 Native 入口，连接真实 Core 函数；实机验收仍待完成。
- 配置读取/编辑/保存，包含验证、修订冲突检查、未知字段保留、备份和原子替换。
- 真实进度/错误流、有容量限制且脱敏的日志、搜索/筛选/复制、用户报告的匹配历史和报告导出。
- 官方 stable/preview 版本查询与原帮助内容的限定摘要，不自动安装。
- 保留原十种语言资源：zh-CN、en、ja、ko、ru、es、de、fr、pt-BR、zh-TW。可选择语言，新增 Native 文案尚未全部翻译，缺失时回退英文。

刷新保持只读。写入、SSH 和启动必须主动执行并授权；具体 Guest、性能及 Wi-Fi 变更还需额外确认。取消会尝试支持的恢复，已经启动的进程可能继续运行。中断后请重新核对实际状态。

## 系统要求

Apple Silicon、macOS 14+、包含 macOS SDK 的完整 Xcode、Python 3.9+。运行环境操作还需要已有完整旧启动器目录，包含原验证版本 FX/gvproxy 资源及兼容的 SSH 配置。App 不安装、移动或静默选用运行资源。

暂无已签名/公证、可直接安装的发行版。不捆绑运行时二进制、游戏文件、字体、凭据或 Guest 镜像。

## 安装与使用

```sh
git clone --branch feature/macos-native-app --recurse-submodules https://github.com/LSJOP/helldivers2-fx-launcher.git
cd helldivers2-fx-launcher/native-app
./script/build_and_run.sh --xcode-only
open build/Debug/HD2FXNative.app
```

已有克隆切换分支后，在仓库根目录执行 `git submodule update --init --recursive`。源码 ZIP 不含子模块。固定归档提供元数据适配器、选定原 Core 源码和语言资源。打包不执行启动操作或下载依赖。

设置可选语言、外观和已有 Python 解释器（默认 `/usr/bin/python3`）。界面偏好和运行根目录选择仅在本次会话生效。打开对应操作面板，需要时选择已有完整旧目录，授权前核对变更。仅打开页面不会执行实机操作。

配置：`~/Library/Application Support/Helldivers2FXLauncher/settings.json`。编辑器显示目标/修订，替换前备份。Native 诊断/报告：`~/Library/Application Support/Helldivers2FXLauncher/native`。原恢复凭据还可能写入选定旧目录。秘密通过 stdin 传递，不进入命令参数；钥匙串使用由原 SSH 配置控制。连接前核对认证与目标设置。

## 尚未实现或尚未验证

- FX/Guest/SSH/Steam 执行、EAC 和多人联机需要用户主动执行并取得新鲜实机证据。隔离检查/编译不证明游戏或匹配成功。
- 原二进制/目标保护保持生效，任意 FX 版本不能直接互换。
- 完整 Native 翻译、完整帮助/更新日志呈现及更全面环境报告仍为部分迁移。
- 归档菜单未实现 FX 版本切换或自动更新安装。
- CrossOver、单独授权的总览士兵素材、签名/公证仍待后续处理。不使用整张 UI 预览图充当素材。
- 当前 token 缺少 `workflow` 权限，GitHub Actions 配置尚未发布，请使用本地检查。

文件存在、服务运行、网络可达、SSH 认证和游戏服务可用是不同证据。启动不证明 EAC/联机；录入匹配结果仍属于用户报告。

## 分支与原脚本归档

- [main](https://github.com/LSJOP/helldivers2-fx-launcher/tree/main)：Native 主线，可能落后于开发分支。
- [feature/macos-native-app](https://github.com/LSJOP/helldivers2-fx-launcher/tree/feature/macos-native-app)：当前迁移开发。
- [legacy-script](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script)：保留脚本历史及固定兼容补充，本次迁移不修改。

终端启动器：[归档 README](https://github.com/LSJOP/helldivers2-fx-launcher/blob/legacy-script/README.md)、[脚本 ZIP](https://github.com/LSJOP/helldivers2-fx-launcher/archive/refs/heads/legacy-script.zip)。旧 main.zip 链接现在下载 Native 源码，脚本专属链接请将 main 改为 legacy-script。原始基线：[0205aca](https://github.com/LSJOP/helldivers2-fx-launcher/tree/0205acaec3b32024df180a6dfb8ecc587e2f1914)。未删除任何 Release/Tag。

## 开发与许可

遵循 [AGENTS.md](AGENTS.md)，集中修改；相关 Bridge/服务/打包行为变化时执行 `native-app/script/run_checks.sh`。检查使用临时数据，不启动真实游戏。本 README 与[英文版](README.md)必须同步；仅修改文档时检查链接，不编译 App。

尚未选定项目统一源码许可证，不应推定均可再分发。HELLDIVERS 2 标识归各权利人所有。战术几何由代码绘制，不捆绑官方美术。见[权利与来源说明](THIRD_PARTY_NOTICES.md)及归档声明。
