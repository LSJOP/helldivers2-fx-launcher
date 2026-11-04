# 真实环境结果

验收日期：2026-11-05（Asia/Shanghai）。源码基线 `8ba547c390d52971a7740a1970411c9e153c44b7`；验收分支 `audit/full-acceptance-20261105`。修复构建提交及 SHA-256 以候选目录的 SOURCE-COMMIT.txt / executable-sha256.txt 为准。基线 App 0.1.0 / 2026110411；修复构建 App 0.1.0 / 2026110501。未声称已发布 v1.0.0。

证据根：`native-app/evidence/`（本地忽略，交付时复制到候选 Evidence）。PASS 只适用于记录的范围；单元/隔离替身结果不代表真实 Guest 或游戏。未执行的真实项目一律 NOT TESTED，缺少前提的项目 BLOCKED。截图为真实 Debug App 窗口，非模拟 UI；抽查不代表全部交互已验收。

## 已执行

- 实际读取并严格签名校验 FX 1.9.4、1.9.8、1.9.9；摘要在 host-readonly.json。
- 生产 Swift NativeCoreService 对实际 1.9.8/1.9.9 调用发现、资源检查、运行状态；FX 均未运行。实际发现缺陷及修复复测分别在 host-native-results.jsonl / host-native-retest.jsonl。
- 独立 Debug capture bundle ID，zh-CN/en 各七页面+三个详情区域，20 张真实窗口截图。仅进程偏好隔离；底层配置只读读取现有 App Support，因此不是完整干净用户首次安装验收。
- 独立 Release 副本 8 秒存活、仅终止本次创建进程，不等于 Release GUI 验收。

## 待用户授权的操作

1. 明确指定 FX 1.9.8 或 1.9.9 路径，授权启动 FX/Guest，以进行真实身份绑定、SSH 和独立只读 sudo 检查；密码仅在 App 安全输入框输入，不在聊天提供。
2. 授权 Steam/游戏启动后验证主菜单；单人任务及多人任务分别确认实际结果。
3. IPv6、FX 性能参数、首次部署写入仍需逐项精确目标/原值/新值/备份/恢复预览后授权；本报告不是批量修改申请。
4. 更新安装限隔离副本，但需先有可信签名包；缺少包不能靠授权绕过。

上述尚未授权/执行，均 NOT TESTED 或 BLOCKED。没有关闭/绕过反作弊，没有更改 sudoers/NOPASSWD，没有删除/替换虚拟磁盘或升级运行组件。

修复版 Release：3次有界启动/窗口检测/退出，实际 on-screen window 均为1。仅4秒/轮、单台系统、隔离 bundle ID，无 Guest；完整稳定性仍 NOT TESTED。证据位于候选 release-gui-results.json/release-window.png。

## 收尾状态变化

收尾进程检查发现 `/Applications/FX 绝地潜兵2（脚本专用）.app` 的 FX 1.9.4 进程7797/7801及gvproxy正在运行，进程开始时间2026-11-05 02:29:47（本地）。早先 HOST-02 的未运行结果只对应当时快照。启动来源未经确认，本任务未主动发出 FX 启动操作，不把外部状态变化计为启动 PASS；未连接 Guest、未终止这些进程。真实 SSH/Guest/游戏验收仍需用户授权。
