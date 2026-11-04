# GUI 与十语言验收

验收日期：2026-11-05（Asia/Shanghai）。源码基线 `8ba547c390d52971a7740a1970411c9e153c44b7`；验收分支 `audit/full-acceptance-20261105`。修复构建提交及 SHA-256 以候选目录的 SOURCE-COMMIT.txt / executable-sha256.txt 为准。基线 App 0.1.0 / 2026110411；修复构建 App 0.1.0 / 2026110501。未声称已发布 v1.0.0。

证据根：`native-app/evidence/`（本地忽略，交付时复制到候选 Evidence）。PASS 只适用于记录的范围；单元/隔离替身结果不代表真实 Guest 或游戏。未执行的真实项目一律 NOT TESTED，缺少前提的项目 BLOCKED。截图为真实 Debug App 窗口，非模拟 UI；抽查不代表全部交互已验收。

GUI-01 / L10N-01 PASS（限定范围）。真实捕获 zh-CN/en 七页面加详情，共20 PNG，含每图 SHA-256。人工视觉抽查四张：zh 首次配置、zh 环境网络、zh 性能动作、en 设置更新；无明显截断，正确显示未知、未检测、未验证，密码框及独立会话提示存在。其余图片只验证捕获成功，未逐张人工检查。

十语言：en/zh-CN/zh-TW/ja/ko/ru/es/de/fr/pt-BR，各581必需键；静态覆盖与8负向检查通过。未删语言。未把 technical name（Steam/PlayFab/Vulkan/SSH/sudo）视为翻译遗漏。自然度、全部错误、所有动态弹窗、剩余八语言视觉/窄窗口/全部主题/真实任务状态交互均 NOT TESTED。

GUI 总体验收与十语言完整验收均 NOT TESTED。首次安装不是干净 macOS 用户沙箱：capture ID 隔离偏好，但 CoreFS 仍只读读取现有 App Support。因此不能标记 FIRST RUN PASS。

修复 README 七页面与“选择原脚本目录”矛盾、更新双语未发布记录；App UI 无布局变化，保留现有 README 截图，本次捕获仅作为基线证据，不冒充修复 build 2026110501 截图。

## 修复候选 Release 实测补充

连续3次实际启动各显示1个主窗口；首轮截图已检查。发现首页 `ui.180` 仍要求指定既有运行目录，十语言资源均残留旧前提，列 P2-04 OPEN。故 GUI ACCEPTANCE 改为 FAIL，不宣称中文完全正确。本次没有修改界面文案或将旧截图替换为未验证新图。

## 启动成功后自动关闭弹窗

用户提供真实成功后仍显示启动弹窗的截图。修复仅在当前launch_game请求成功返回、game_process_detected=true、任务未取消、generation仍匹配、当前弹窗仍为launch_game时清除operationSelection。失败/取消/未检测到进程或其他弹窗均不自动关闭；不清除会话密码、不修改启动核心/Guest/游戏。未新增UI文案，十语言资源无需增删。现有截图保持其来源身份；新的成功后自动关闭截图及真实GUI复核待下一次用户启动，不为截图重启正在运行的游戏。

## 首页首次配置入口去重

移除DashboardView主视觉上方的重复首次运行环境配置按钮，保留侧边栏及setup页面，不改启动/配置/凭据行为。Debug build 2026110503通过；真实zh-CN/en独立窗口顶部无重复按钮，侧边栏入口仍在。仅两张Dashboard截图已更新及检查，初始只读快照尚在加载；不将捕获成功计为运行状态验收。使用既有十语言键，无删语言。

## FX 本地测试副本

用户要求显示和允许本地测试副本启动；已加入相应识别和十语言本地副本标记。中英文FX管理页build2026110505真实截图均显示标准版与测试版两个条目。截图不包含实际FX启动或Guest密码认证；这两项不由截图推断。

## Encrypted local remembering

Current user policy is local encrypted persistence, no macOS Keychain. Ten-language Settings and First-Run Setup credential text, saved status, deletion action and storage error text updated. Refresh only affected bilingual Settings/First-Run Setup screenshots; other screenshots retain their own provenance. Historical memory-only results remain historical.
