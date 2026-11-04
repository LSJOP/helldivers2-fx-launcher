# 安全审计

验收日期：2026-11-05（Asia/Shanghai）。源码基线 `8ba547c390d52971a7740a1970411c9e153c44b7`；验收分支 `audit/full-acceptance-20261105`。修复构建提交及 SHA-256 以候选目录的 SOURCE-COMMIT.txt / executable-sha256.txt 为准。基线 App 0.1.0 / 2026110411；修复构建 App 0.1.0 / 2026110501。未声称已发布 v1.0.0。

证据根：`native-app/evidence/`（本地忽略，交付时复制到候选 Evidence）。PASS 只适用于记录的范围；单元/隔离替身结果不代表真实 Guest 或游戏。未执行的真实项目一律 NOT TESTED，缺少前提的项目 BLOCKED。截图为真实 Debug App 窗口，非模拟 UI；抽查不代表全部交互已验收。

SEC-01/02 源码及隔离检查 PASS，完整真实安全验收 NOT TESTED。

- 没有 SecItem*/SecKeychain* 凭据 API；SessionCredentialManager 不依赖 UserDefaults/FileManager/Security/CryptoKit。签名与更新仍可合法使用 Security。历史 CoreSnapshot 保留不修改。
- SSH/sudo 分开存内存；canonical FX/config/process/Guest boot 绑定，失败/变更清除及递归日志脱敏有隔离检查。Swift String 的清除不等于物理内存零化；未做内存转储证明。
- 生产 SSH 传输 openpty，密码不入 argv/env；独立 sudo 使用 -k -S，stdin 传入、目标脚本 stdin 关闭；没有改 sudoers 或添加 NOPASSWD。35 SSH 与30特权隔离检查通过，不等于真实密码通过。
- 首次 SSH 使用 StrictHostKeyChecking=accept-new，后续独立命令严格校验；接受新 key 仍依赖本机 FX/网络祖先与 Guest 身份绑定，并非预置远端 key。真实 host-key 变化场景未测。
- IPv6 只在显式配置路径，预览/确认/收据/恢复；诊断与 CheckingCompatibility 不写入。
- 本次未输入真实密码；未对现有用户日志/全部临时文件做破坏性清理，也未证明未来所有失败路径无泄漏。真实凭据重启/错误/日志验收待进行。
- 信任校验与反作弊保持；没有放宽 FX 1.9.9、签名、hash 或包审批门禁。

结论：局部安全审计 PASS；完整 SECURITY AUDIT = NOT TESTED，阻止无条件发布。
