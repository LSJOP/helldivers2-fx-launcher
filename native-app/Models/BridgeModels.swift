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
    struct Failure: Decodable, Sendable { let code: String; let message: String }
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
    var id: String { code + method }
    var errorDescription: String? { code }
    init(_ code: String, method: String = "bridge") { self.code = code; self.method = method }
    func message(_ zh: Bool) -> String {
        switch code {
        case "TIMEOUT": return zh ? "读取超时。请重试。" : "The read timed out. Please retry."
        case "CANCELLED": return zh ? "读取已取消。" : "The read was cancelled."
        case "PYTHON_UNAVAILABLE": return zh ? "Python 不可用。请在设置中选择已有的 Python 3.9 或更新版本。" : "Python is unavailable. Select an existing Python 3.9 or newer in Settings."
        case "BRIDGE_EXITED": return zh ? "读取进程异常退出。请刷新重试。" : "The bridge exited unexpectedly. Refresh to retry."
        case "PROTOCOL_ERROR", "PROTOCOL_MISMATCH": return zh ? "通信协议不匹配或响应损坏。" : "The protocol is incompatible or the response is invalid."
        case "CORE_UNAVAILABLE": return zh ? "无法读取 Core 数据。请检查 App 是否完整。" : "Core data is unavailable. Check that the app bundle is intact."
        case "OUTPUT_LIMIT": return zh ? "响应超过大小限制。" : "The response exceeded the size limit."
        case "NOT_IMPLEMENTED": return zh ? "此接口尚未实现。" : "This interface is not implemented."
        case "BUSY": return zh ? "读取正在进行中。" : "A read is already in progress."
        default: return zh ? "读取失败。请重试或检查 App 文件。" : "The read failed. Retry or check the app files."
        }
    }
}
