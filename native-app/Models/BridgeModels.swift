import Foundation

indirect enum JSONValue: Codable, Sendable, Equatable {
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


struct CoreReply: Sendable {
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
    func message(_ zh: Bool) -> String { message(zh ? "zh-CN" : "en") }
    func message(_ language: String) -> String {
        switch code {
        case "TIMEOUT": return NativeStrings.text("ui.344", language: language)
        case "CANCELLED": return NativeStrings.text("ui.345", language: language)
        case "PYTHON_UNAVAILABLE": return NativeStrings.text("ui.240", language: language)
        case "BRIDGE_EXITED": return NativeStrings.text("ui.336", language: language)
        case "PROTOCOL_ERROR", "PROTOCOL_MISMATCH": return NativeStrings.text("ui.347", language: language)
        case "CORE_UNAVAILABLE": return NativeStrings.text("ui.082", language: language)
        case "OUTPUT_LIMIT": return NativeStrings.text("ui.350", language: language)
        case "NOT_IMPLEMENTED": return NativeStrings.text("ui.356", language: language)
        case "BUSY": return NativeStrings.text("ui.002", language: language)
        case "RUNTIME_ROOT_REQUIRED": return NativeStrings.text("ui.301", language: language)
        case "SOURCE_MISMATCH", "LAUNCHER_FILES_MISSING": return NativeStrings.text("ui.178", language: language)
        case "FX_UNAVAILABLE": return NativeStrings.text("ui.352", language: language)
        case "GVPROXY_UNAVAILABLE": return NativeStrings.text("ui.346", language: language)
        case "NODE_UNAVAILABLE": return NativeStrings.text("ui.013", language: language)
        case "SSH_UNAVAILABLE": return NativeStrings.text("ui.012", language: language)
        case "FX_PROFILE_MISMATCH": return NativeStrings.text("ui.331", language: language)
        case "FX_START_FAILED": return NativeStrings.text("ui.123", language: language)
        case "FX_IDENTITY_UNVERIFIED": return NativeStrings.text("ui.330", language: language)
        case "FX_INSTANCE_MISMATCH": return NativeStrings.text("ui.351", language: language)
        case "FX_ENTRY_MISMATCH": return NativeStrings.text("ui.341", language: language)
        case "SSH_CONNECTION_FAILED": return NativeStrings.text("ui.143", language: language)
        case "AUTH_REQUIRED":
            if details["credential_kind"]?.text == "sudo_password" { return NativeStrings.text("ui.333", language: language) }
            if details["credential_kind"]?.text == "passphrase" { return NativeStrings.text("ui.335", language: language) }
            return NativeStrings.text("ui.332", language: language)
        case "GUEST_TRANSACTION_FAILED": return NativeStrings.text("ui.334", language: language)
        case "FX_NOT_RUNNING": return NativeStrings.text("ui.353", language: language)
        case "LOCAL_FX_REQUIRED": return NativeStrings.text("ui.355", language: language)
        case "GUEST_INSPECTION_FAILED": return NativeStrings.text("ui.146", language: language)
        case "SSH_AUTH_FAILED": return NativeStrings.text("ui.289", language: language)
        case "SUDO_AUTH_FAILED": return NativeStrings.text("ui.147", language: language)
        case "CREDENTIAL_SCOPE_CHANGED": return NativeStrings.text("ui.354", language: language)
        case "SENSITIVE_CONFIGURATION", "SENSITIVE_CHANGE_BLOCKED": return NativeStrings.text("ui.231", language: language)
        case "COMPATIBILITY_CHECK_FAILED": return NativeStrings.text("ui.070", language: language)
        case "STEAM_START_FAILED": return NativeStrings.text("ui.322", language: language)
        case "GAME_START_FAILED": return NativeStrings.text("ui.340", language: language)
        case "GAME_EXITED": return NativeStrings.text("ui.199", language: language)
        case "EAC_CHECK_FAILED": return NativeStrings.text("ui.339", language: language)
        case "CHANGE_CONFIRMATION_REQUIRED": return NativeStrings.text("ui.275", language: language)
        case "CONFIRMATION_REQUIRED": return NativeStrings.text("ui.112", language: language)
        case "ENVIRONMENT_CHECK_FAILED", "LAUNCH_FAILED": return NativeStrings.text("ui.177", language: language)
        default: return NativeStrings.text("ui.348", language: language)
        }
    }
}


enum GUIAction: String, CaseIterable, Identifiable {
    case connect = "connect_fx", inspect = "inspect_guest_environment", fxState = "check_fx_state"
    case startFX = "start_fx", steam = "start_steam", game = "launch_game"
    var id: String { rawValue }
    var labelKey: String {
        switch self {
        case .connect: return "ui.079"
        case .inspect: return "ui.159"
        case .fxState: return "ui.048"
        case .startFX: return "ui.316"
        case .steam: return "ui.317"
        case .game: return "ui.176"
        }
    }
    var needsReview: Bool { self == .startFX || self == .steam || self == .game }
    func accepts(_ result: [String: JSONValue]) -> Bool {
        switch self {
        case .connect: return result["ssh_connected"]?.boolean == true && result["guest_ready"]?.boolean == true
        case .inspect:
            guard case .object(let components) = result["components"] else { return false }
            return result["ssh_connected"]?.boolean == true && result["guest_ready"]?.boolean == true && result["guest_os"]?.text != nil && ["steam_files","game_manifest","game_directory","game_executable","proton_files","fex_files"].allSatisfy { components[$0]?.boolean != nil }
        case .fxState: return result["fx_host_running"]?.boolean != nil
        case .startFX: return result["fx_host_running"]?.boolean == true
        case .steam: return result["ssh_connected"]?.boolean == true && result["steam_running"]?.boolean == true
        case .game: return result["game_process_detected"]?.boolean != nil
        }
    }
}

enum GUIOperationStatus: String { case idle, running, succeeded, failed, cancelled, timedOut }
struct GUIOperationRecord {
    let method: String
    let target: String
    let startedAt = Date()
    var endedAt: Date?
    var status: GUIOperationStatus = .running
    var error: ErrorState?
    mutating func finish(_ failure: ErrorState? = nil) {
        endedAt = Date(); error = failure
        status = failure == nil ? .succeeded : failure?.code == "CANCELLED" ? .cancelled : failure?.code == "TIMEOUT" ? .timedOut : .failed
    }
}

/// One resource-backed source for Native UI text. Missing translations are visible
/// errors, never an implicit English success; the development gate rejects them.
enum NativeStrings {
    static let languages = ["zh-CN", "en", "ja", "ko", "ru", "es", "de", "fr", "pt-BR", "zh-TW"]
    static let catalog: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "native-locales", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode([String: [String: String]].self, from: bytes) else { return [:] }
        return value
    }()
    static func text(_ key: String, language: String) -> String {
        catalog[language]?[key] ?? "⟦" + language + ":" + key + "⟧"
    }
}
