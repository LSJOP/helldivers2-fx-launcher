# HELLDIVERS 2 FX Launcher — macOS 原生 App

[English](README.md) | [简体中文](README.zh-CN.md)

采用 **SwiftUI + 小范围 AppKit 集成**构建的 macOS 战术终端，用于 HELLDIVERS 2 FX Launcher。**当前为 Native Phase 1：只读开发预览。** 本项目为非官方项目，不宣称获得官方认可。

## 当前状态与已实现功能

| 范围 | 当前可用内容 |
| --- | --- |
| 页面导航 | 原生侧边栏、总览、运行环境、FX 管理、日志和设置；支持 Cmd+1…5 切换页面、Cmd+R 刷新 |
| 界面 | 中英文功能文案；默认深色，可选浅色或跟随系统；偏好仅在当前会话生效 |
| 主机检查 | 通过受监督的 Python JSONL Bridge 读取真实 macOS、架构和 Python 元数据 |
| 依赖检查 | 本地文件存在性，以及限定范围内的 FX 版本和结构元数据；发现文件不代表运行就绪 |
| 日志 | 当前会话的 App 与只读 Bridge 日志；尚不能读取历史游戏日志 |
| 开发分支新增内容 | `feature/macos-native-app` 提供五页统一战术布局，以及日志搜索、等级筛选和复制。原始记录没有等级字段时保持“未标级”。这些新增内容尚未合并至 main。 |

游戏启动功能**保持禁用**，界面显示明确原因。FX 运行状态、Guest、SSH、EAC 和多人联机均**未验证**。Phase 1 不安装或更新软件、不启动游戏、不写入启动器设置。

## 系统要求

- 搭载 Apple Silicon 的 Mac，运行 macOS 14 或更新版本。
- 用于本地构建的完整 Xcode 及 macOS SDK。
- 已安装的 Python 3.9 或更新版本解释器。

目前**没有**可直接安装、已签名并公证的 Native 发布包。项目不附带运行时二进制、游戏文件、字体、凭据或 Guest 映像。

## 安装与使用

在本机构建 main：

```sh
git clone --recurse-submodules https://github.com/LSJOP/helldivers2-fx-launcher.git
cd helldivers2-fx-launcher/native-app
./script/build_and_run.sh --xcode-only
open build/Debug/HD2FXNative.app
```

如需使用开发分支的新增内容，请改为克隆该分支：

```sh
git clone --branch feature/macos-native-app --recurse-submodules https://github.com/LSJOP/helldivers2-fx-launcher.git
```

已有克隆在切换到目标分支后，先于仓库根目录执行 `git submodule update --init --recursive`。`CoreSnapshot` 子模块固定到归档提交，远程分支更新不会自动改变构建输入。构建只将七个白名单兼容模块及 VERSION 复制到 App，不执行旧脚本启动入口，也不下载或安装依赖。

在设置中选择中文或英文，以及深色、浅色或跟随系统外观。选项只在当前 App 会话生效。默认解释器为 `/usr/bin/python3`；如果不可用，可选择本机已有的合适解释器后刷新。找到依赖文件或 FX 候选并不代表游戏环境已经可用。

Native 源码 ZIP **不包含**子模块内容，请使用上述递归克隆方式。

## 尚未实现或尚未验证

- Native 游戏启动、运行版本切换、自动安装及更新尚未开放。
- CrossOver 集成及恢复旧脚本全部十种界面语言仍属后续工作；Native 当前提供中文和英文。
- 主机元数据、文件存在性或应用结构匹配，不能证明 FX、Guest、SSH、Steam、EAC 或多人联机及游戏运行已验证。
- 开发分支预留了首页士兵主视觉容器，但尚未接入独立授权素材；没有将整张 UI 预览图当作背景。
- 分发签名、公证及可直接安装的 Native 发布包仍待完成。
- GitHub Actions 尚未启用：当前 OAuth 令牌缺少发布工作流配置所需的 `workflow` 权限；请使用文档中的本地检查方式。

## 分支与原脚本归档

- [`main`](https://github.com/LSJOP/helldivers2-fx-launcher/tree/main)：Native App 正式主线。
- [`feature/macos-native-app`](https://github.com/LSJOP/helldivers2-fx-launcher/tree/feature/macos-native-app)：Native 日常开发分支。
- [`legacy-script`](https://github.com/LSJOP/helldivers2-fx-launcher/tree/legacy-script)：原 FX Launcher 完整脚本与提交历史，以及 Native 只读兼容快照。

终端启动器请访问[归档脚本 README](https://github.com/LSJOP/helldivers2-fx-launcher/blob/legacy-script/README.md)，或下载[脚本 ZIP](https://github.com/LSJOP/helldivers2-fx-launcher/archive/refs/heads/legacy-script.zip)。已有脚本安装不会被本次迁移修改。旧 `main.zip` 链接现在下载 Native 源码，旧 raw/main 脚本路径不再有效；访问旧脚本时，请将链接中的 `main` 改为 `legacy-script`。迁移前提交 [0205aca](https://github.com/LSJOP/helldivers2-fx-launcher/tree/0205acaec3b32024df180a6dfb8ecc587e2f1914) 仍可访问。没有删除已有 Release 或 Tag。

## 开发与文档维护

按 [AGENTS.md](AGENTS.md) 执行批量开发与最小必要验证。Bridge、打包或服务行为变化时，使用 `native-app/script/run_checks.sh`。仅修改 README 时只检查文档和链接，不编译或启动 App。本文与[英文版](README.md)必须同步维护，保持功能、版本、安装说明和开发状态一致。

## License 与权利说明

仓库**尚未选定覆盖整个项目的源码许可证**，请勿据此假定整个仓库已获再分发许可。HELLDIVERS 2 及相关标识归各自权利人所有。战术几何图形由代码绘制，项目不附带官方游戏美术素材。实际范围和未决许可问题见[权利与来源说明](THIRD_PARTY_NOTICES.md)，以及 `legacy-script` 分支中的历史声明。
