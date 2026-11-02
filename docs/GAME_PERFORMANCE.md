# Game Performance / 游戏性能配置

Status: read-only hardware detection, baseline comparison and local inference framework. Applying/restoring inferred profiles is disabled. A main-menu success record is not a performance benchmark.

## Sources and rules

- Archive: pinned `native-app/CoreSnapshot`, `launcher-20261026/performance_profile.py:SETTINGS` and `goal-dxmt-20261026/start-hd2.py`. No archive files are changed.
- Hardware: original `apple_silicon.detect` reads the exact Apple chip, unified memory and one matching built-in GPU's core count. Native additionally reads physical CPU cores and macOS version. Unknown fields stay unknown; hardware catalog maxima are never used.
- Preferences: original `performance_profile.read_setting` reads only the five existing keys in `es.fxgam.steamac`. Read failures remain unknown. These are stored preferences, not evidence of effective Guest settings.
- `GamePerformanceInferenceService` is deterministic and local. Exact Apple M4 Pro + 24 GiB plus the unchanged reference values yields **Local baseline · Candidate**, not verified performance. All other hardware yields **No suitable profile**. No external AI or GPU performance multipliers are used.

| Parameter | Recorded value | Purpose / class | Safe automatic range | Compatibility / restart |
| --- | --- | --- | --- | --- |
| cpus | 8 | Virtual CPUs; performance parameter | Not established across devices; inference disabled | Guest restart required for effect |
| memMiB | 8192 | Guest memory; performance parameter | Not established across devices; inference disabled | Guest restart required for effect |
| vulkanDriver | kosmickrisp | Fixed compatibility parameter | No automatic inference | Changing driver can affect compatibility; restart |
| metalHUD | false | Recorded display/diagnostic preference | No automatic inference | Runtime effect unverified; restart may be needed |
| superResolution | false | Recorded display/compatibility preference | No automatic inference | Runtime effect unverified; restart may be needed |
| steamac.gpu_mib | 6144 | Recorded fixed launch-entry GPU budget | No automatic inference or write | Not a measured current Guest value; restart |
| chip / CPU / GPU / memory / macOS | Actual read-only device values | Current-device environment | Detected only, never copied to another device | No changes |
| EAC / sudo / permissions / SSH address / game path / unknown settings | Not inferred | Prohibited automatic inference | None | Not modified |

## Why Apply and Restore are disabled

The archived apply handler writes FX preferences and delegates to the full configure-only launcher, including additional Guest compatibility checks/changes. It does not provide a standalone, parameter-scoped apply-and-restore API for inferred profiles. Reusing it as an inferred-profile writer would exceed the new page's scope. It remains available through the existing explicit advanced operation; it is not called by this page.

Before enabling writes, require independently validated bounds, target/current-value conflict checks, per-parameter backups before confirmation, atomic or reversible application, read-back verification, and restoration of only this operation's actual changes. Never restore passwords or unknown configuration. Experimental profiles must display the full visible warning and must never apply automatically.

当前页面仅做真实硬件／偏好读取、候选基准比较和本地规则判断。M4 Pro／24 GiB 不是全面性能验收；其他硬件没有可靠边界时不推算。应用／恢复禁用且有可见原因，不创建备份或修改 FX、Guest、EAC、权限、连接地址及原游戏启动参数。
