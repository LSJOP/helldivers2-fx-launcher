# SteamOS network settings and diagnostics

位置：**运行环境 → SteamOS 网络设置**。IPv6 不再是启动 HELLDIVERS 2 的强制条件；CheckingCompatibility 不写 IPv6，也不因开启、关闭、混合或未知的 IPv6 状态而阻断启动。FX/Guest 身份、SSH、组件哈希、代理和其他原有安全检查保留。

先通过现有连接操作验证 Guest，再点击“读取 Guest 状态”。开关读取 Guest 的四个运行时 `disable_ipv6` 控制项：all、default、eth0、lo；0允许、1禁用。值混合时显示“配置不一致”，不自动修复。允许这些控制项不证明 IPv6 地址、路由、DNS或端到端连接可用。Guest断开/身份未验证时不可修改。

主动操作开关后显示当前/目标值和影响范围，用户确认本次计划并在安全字段输入当前会话 sudo 凭据才可写入。每次独立 SSH 特权调用都在自身调用内认证，不依赖先前时间戳。密码不进入argv、环境、文件或日志，也不访问Keychain。状态仅在当前Guest boot有效，重启后可能变化，不写sysctl.d。

修改all会影响其他接口；事务保存完整接口快照，修改四个控制项并还原其他接口的原值。root命令再次核对boot、接口集合、旧值和无游戏运行，再写入并读回验证。应用本地私有目录保存不含凭据的收据。失败尝试有界恢复，恢复失败展示真实残留值；手动“恢复修改前配置”同样预览/确认，必须有可信收据且FX可执行指纹与进程实例、Guest boot、接口及当前值没有无法解释的漂移；同一目标重新SSH认证不会单独使收据失效。无可信快照不猜测原值。恢复sysctl值不保证还原此前IPv6连接或地址生命周期。

**运行环境 → 网络诊断** 是独立只读功能，手动开始/重测/取消，不写IPv6、代理、DNS、防火墙、路由、Steam、游戏或反作弊，不申请sudo。只读指不改配置，探测本身会发送少量有界流量。

- VM：已验证Guest的SSH请求往返；不是外网速度。
- Steam TLS：Host经127.0.0.1:7890代理访问store.steampowered.com:443，验证服务器证书；curl完成TLS后发HEAD。缺少代理、游戏在运行或游戏状态未知时暂停。
- PlayFab：Guest直连与经192.168.127.254:7890代理分别访问title.playfabapi.com:443；验证证书，不携带账户数据，不要求Steam登录。
- UDP：Guest向stun.cloudflare.com:3478和stun.l.google.com:19302各发送两次STUN Binding Request；核对响应类型、cookie、随机事务ID与长度，统计成功数、往返和同目标差值。查看Guest UDP计数差及游戏socket数量，不显示对端地址。时延包含SSH与身份检查开销，不与原脚本纯Guest测时直接比较。

NOT_TESTED=尚未执行；RUNNING=执行中；PAUSED=缺少会话/游戏未确认空闲/代理未就绪；PASS=该探测范围通过；FAIL=该次明确失败；TIMEOUT=有界等待结束而结果不确定；UNSUPPORTED=缺工具；CANCELLED=取消；UNVERIFIED=证据不足。UDP至少2次有效响应才标PASS，同时显示n/4，1次仅UNVERIFIED。PlayFab一条通路成功不表示两条都成功，详情逐条列出。

这些结果不证明Steam登录、NAT类型、P2P、游戏能启动或多人联机成功。历史UDP后台hook已迁为显式操作，诊断结果不会阻断游戏启动。

English: **Environment → SteamOS network settings** owns runtime IPv6 enable/disable and confirmed snapshot recovery. IPv6 is optional and never changed by game startup. **Network diagnostics** runs explicit, cancellable, bounded VM/Steam TLS/PlayFab/UDP probes without sudo or configuration changes. Secrets stay in process memory. PASS is scoped reachability evidence, never multiplayer acceptance. See the parity audit and migration report for source locations and live-test limits.

Primary references: [Linux IPv6 sysctl semantics](https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html), [STUN RFC 8489](https://www.rfc-editor.org/rfc/rfc8489.html). In particular, reading conf/all alone is not proof of all-interface IPv6 availability.
