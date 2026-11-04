# GUI 与十语言验收

验收日期：2026-11-05（Asia/Shanghai）。源码基线 `8ba547c390d52971a7740a1970411c9e153c44b7`；验收分支 `audit/full-acceptance-20261105`。修复构建提交及 SHA-256 以候选目录的 SOURCE-COMMIT.txt / executable-sha256.txt 为准。基线 App 0.1.0 / 2026110411；修复构建 App 0.1.0 / 2026110501。未声称已发布 v1.0.0。

证据根：`native-app/evidence/`（本地忽略，交付时复制到候选 Evidence）。PASS 只适用于记录的范围；单元/隔离替身结果不代表真实 Guest 或游戏。未执行的真实项目一律 NOT TESTED，缺少前提的项目 BLOCKED。截图为真实 Debug App 窗口，非模拟 UI；抽查不代表全部交互已验收。

GUI-01 / L10N-01 PASS（限定范围）。真实捕获 zh-CN/en 七页面加详情，共20 PNG，含每图 SHA-256。人工视觉抽查四张：zh 首次配置、zh 环境网络、zh 性能动作、en 设置更新；无明显截断，正确显示未知、未检测、未验证，密码框及独立会话提示存在。其余图片只验证捕获成功，未逐张人工检查。

十语言：en/zh-CN/zh-TW/ja/ko/ru/es/de/fr/pt-BR，各581必需键；静态覆盖与8负向检查通过。未删语言。未把 technical name（Steam/PlayFab/Vulkan/SSH/sudo）视为翻译遗漏。自然度、全部错误、所有动态弹窗、剩余八语言视觉/窄窗口/全部主题/真实任务状态交互均 NOT TESTED。

GUI 总体验收与十语言完整验收均 NOT TESTED。首次安装不是干净 macOS 用户沙箱：capture ID 隔离偏好，但 CoreFS 仍只读读取现有 App Support。因此不能标记 FIRST RUN PASS。

修复 README 七页面与“选择原脚本目录”矛盾、更新双语未发布记录；App UI 无布局变化，保留现有 README 截图，本次捕获仅作为基线证据，不冒充修复 build 2026110501 截图。
