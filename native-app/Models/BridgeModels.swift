import Foundation

indirect enum JSONValue: Codable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var text: String? { if case .string(let v) = self { return v }; return nil }
    var integer: Int? { if case .number(let v) = self, v.isFinite, v >= 0, v < Double(Int.max), v.rounded() == v { return Int(v) }; return nil }
    var boolean: Bool? { if case .bool(let v) = self { return v }; return nil }
    var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
}

struct BridgeResponse: Decodable, Sendable {
    struct Failure: Decodable, Sendable { let code: String; let message: String; let details: [String: JSONValue]? }
    let `protocol`: Int
    let request_id: String
    let ok: Bool
    let result: [String: JSONValue]?
    let error: Failure?
    let observed_at: String?
}

struct BridgeReply: Sendable {
    let result: [String: JSONValue]
    let observedAt: String
    let requestID: String
}

struct ErrorState: Error, LocalizedError, Identifiable, Sendable {
    let code: String
    let method: String
    let details: [String: JSONValue]
    var id: String { code + method }
    var errorDescription: String? { code }
    init(_ code: String, method: String = "bridge", details: [String: JSONValue] = [:]) { self.code = code; self.method = method; self.details = details }
    func message(_ zh: Bool) -> String {
        switch code {
        case "TIMEOUT": return zh ? "操作超时；请先核对实际运行状态。" : "The operation timed out; recheck actual state first."
        case "CANCELLED": return zh ? "操作已取消或中断；请重新检查实际状态。" : "The operation was cancelled or interrupted; recheck actual state."
        case "PYTHON_UNAVAILABLE": return zh ? "Python 不可用。请在设置中选择已有的 Python 3.9 或更新版本。" : "Python is unavailable. Select an existing Python 3.9 or newer in Settings."
        case "BRIDGE_EXITED": return zh ? "读取进程异常退出。请刷新重试。" : "The bridge exited unexpectedly. Refresh to retry."
        case "PROTOCOL_ERROR", "PROTOCOL_MISMATCH": return zh ? "通信协议不匹配或响应损坏。" : "The protocol is incompatible or the response is invalid."
        case "CORE_UNAVAILABLE": return zh ? "无法读取 Core 数据。请检查 App 是否完整。" : "Core data is unavailable. Check that the app bundle is intact."
        case "OUTPUT_LIMIT": return zh ? "响应超过大小限制。" : "The response exceeded the size limit."
        case "NOT_IMPLEMENTED": return zh ? "此接口尚未实现。" : "This interface is not implemented."
        case "BUSY": return zh ? "读取正在进行中。" : "A read is already in progress."
        case "RUNTIME_ROOT_REQUIRED": return zh ? "请先选择已有完整旧启动器目录。" : "Select the existing complete legacy launcher directory."
        case "SOURCE_MISMATCH", "LAUNCHER_FILES_MISSING": return zh ? "启动文件缺失或与归档不匹配；没有执行替代文件。" : "Launch files are missing or differ from the archive; no replacement code was executed."
        case "FX_UNAVAILABLE": return zh ? "指定 FX 缺失、不可执行或哈希不匹配。" : "The selected FX is missing, not executable, or has a different hash."
        case "GVPROXY_UNAVAILABLE": return zh ? "原 gvproxy 或 wrapper 缺失或不匹配。" : "The original gvproxy or wrapper is missing or incompatible."
        case "NODE_UNAVAILABLE": return zh ? "需要已有可验证的 Node 运行环境。" : "An existing validated Node runtime is required."
        case "SSH_UNAVAILABLE": return zh ? "找不到可用 SSH 客户端。" : "An SSH client is unavailable."
        case "FX_PROFILE_MISMATCH": return zh ? "FX 当前配置与原验证组合不符；未自动修改。" : "The FX profile differs from the verified combination; nothing was changed automatically."
        case "FX_START_FAILED": return zh ? "FX 启动或虚拟机等待阶段失败。" : "FX startup or VM readiness failed."
        case "FX_IDENTITY_UNVERIFIED": return zh ? "FX 进程拓扑不明确；未获准写入 Guest。" : "The FX process topology is ambiguous; Guest writes are blocked."
        case "FX_INSTANCE_MISMATCH": return zh ? "当前 FX 实例与选定专用副本不一致。请先检查现有工作，正常退出其他 FX，再通过 Native App 重试；不会自动退出或重置虚拟机。" : "The running FX instance differs from the selected copy. Preserve existing work, quit the other FX normally, then retry from this App. No VM is stopped or reset automatically."
        case "FX_ENTRY_MISMATCH": return zh ? "未验证到原启动入口要求的 gvproxy-eim 进程；这不是 EAC 检测结果。请正常退出该 FX 后由 Native App 按原参数重新启动。" : "The gvproxy-eim process required by the recorded entry was not verified; this is not an EAC result. Quit this FX normally and relaunch through the Native App with the original arguments."
        case "SSH_CONNECTION_FAILED": return zh ? "Guest / SSH 连接需要处理；可在启动面板输入本次认证信息。" : "Guest / SSH needs attention; enter session credentials in the launch panel if required."
        case "AUTH_REQUIRED":
            if details["credential_kind"]?.text == "sudo_password" { return zh ? "需要 Guest 账户的 sudo 密码。请填第三个安全输入框；这不是 macOS 密码。" : "The Guest account sudo password is required in the third secure field; this is not your macOS password." }
            if details["credential_kind"]?.text == "passphrase" { return zh ? "需要 SSH 私钥口令，请填写本次密钥口令。" : "The SSH private-key passphrase is required for this session." }
            return zh ? "需要本次 SSH 密码；Native App 不会读取钥匙串。" : "A session SSH password is required; Native App does not read Keychain."
        case "GUEST_TRANSACTION_FAILED": return zh ? "Guest 事务失败，结果尚未确认；已停止后续变更。请核对原值备份与实际状态后再决定恢复或重试。" : "The Guest transaction failed and its outcome is unverified. Further changes stopped. Inspect the original backup and actual state before recovery or retry."
        case "SUDO_AUTH_FAILED": return zh ? "Guest 拒绝 sudo 授权，本项配置未写入。请核对第三个安全输入框中的 Guest 用户 sudo 密码及其 sudo 权限；不是 macOS 密码。" : "Guest rejected sudo authorization; this configuration change was not written. Check the Guest user sudo password in the third secure field and its sudo permissions; this is not the macOS password."
        case "CREDENTIAL_SCOPE_CHANGED": return zh ? "连接目标或配置已变化，会话凭据未发送。请核对目标后重新输入。" : "The target or configuration changed; credentials were not sent. Verify the target and re-enter them."
        case "SENSITIVE_CONFIGURATION", "SENSITIVE_CHANGE_BLOCKED": return zh ? "配置包含疑似秘密，已停止复制或写入；请手动移除秘密，不会自动删除用户内容。" : "Possible secrets in configuration blocked copying/writing. Remove them manually; user content is not deleted automatically."
        case "COMPATIBILITY_CHECK_FAILED": return zh ? "兼容组件或目标身份检查未通过；现有环境未被重置。" : "Compatibility or target identity checks failed; the existing environment was not reset."
        case "STEAM_START_FAILED": return zh ? "Steam 启动或登录等待失败。" : "Steam startup or login readiness failed."
        case "GAME_START_FAILED": return zh ? "游戏请求失败或未在期限内检测到游戏进程。" : "The game request failed or no game process appeared before the deadline."
        case "GAME_EXITED": return zh ? "最终检查已无游戏进程；不能判定进入游戏。" : "No game process remained at final observation; gameplay is not established."
        case "EAC_CHECK_FAILED": return zh ? "EAC 本次检查未通过；不绕过反作弊。" : "The fresh EAC check failed; anti-cheat is not bypassed."
        case "CHANGE_CONFIRMATION_REQUIRED": return zh ? "需要确认下方具体变更，尚未获准的配置不会写入。" : "Review the exact change below; unapproved configuration is not written."
        case "CONFIRMATION_REQUIRED": return zh ? "需要明确授权本次操作。" : "Explicit consent is required for this action."
        case "ENVIRONMENT_CHECK_FAILED", "LAUNCH_FAILED": return zh ? "启动检查失败，请查看具体阶段和错误详情。" : "Launch checks failed; see the stage and error details."
        default: return zh ? "读取失败。请重试或检查 App 文件。" : "The read failed. Retry or check the app files."
        }
    }
}
