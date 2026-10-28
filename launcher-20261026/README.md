# 启动器源码

完整的公开说明位于项目根目录 [README](../README.md)。当前目录保留原有模块布局，避免仅为发布而重构启动链。

- `menu.py`：终端入口；`legacy_menu.py`：旧版界面。
- `preferences.py` / `keychain_store.py`：用户设置与可选密码存储。
- `network_*.py`：网络操作、诊断与脱敏记录。
- `status_monitor.py` / `performance_profile.py`：状态与性能设置。
- `locales/`、`assets/`：本地语言与图案资源。
- `test_*.py`：离线回归测试；`fixtures/` 只包含公开合成数据。

不要将运行生成的 `backups/`、`reports/` 或任何个人配置上传。
