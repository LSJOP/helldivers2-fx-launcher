import Foundation

/// Pure local rules. Historical catalogue labels never establish performance acceptance.
struct GamePerformanceInferenceService {
    enum Kind { case verified, localBaseline, experimental, unsupported }
    struct Plan {
        let kind: Kind
        let reference: [String: JSONValue]
        let writable = false
    }
    static let reference: [String: JSONValue] = ["cpus": .number(8), "memMiB": .number(8192), "vulkanDriver": .string("kosmickrisp"), "metalHUD": .bool(false), "superResolution": .bool(false)]
    func infer(_ snapshot: [String: JSONValue]) -> Plan {
        let hardware = snapshot["hardware"]?.object ?? [:]
        let source = snapshot["reference"]?.object ?? [:]
        let matchesSource = Self.reference.allSatisfy { key, value in
            guard let observed = source[key] else { return false }
            switch (value, observed) {
            case (.number(let a), .number(let b)): return a == b
            case (.bool(let a), .bool(let b)): return a == b
            case (.string(let a), .string(let b)): return a == b
            default: return false
            }
        }
        guard matchesSource else { return Plan(kind: .unsupported, reference: [:]) }
        let exactDevice = hardware["chip"]?.text == "Apple M4 Pro" && hardware["memory_bytes"]?.integer == 24 * 1024 * 1024 * 1024
        // No interpolation across chips, memory tiers or GPU core counts without validated bounds.
        return Plan(kind: exactDevice ? .localBaseline : .unsupported, reference: source)
    }
    static func render(_ value: JSONValue?) -> String {
        guard let value else { return "—" }
        switch value {
        case .number(let v): return String(format: "%g", v)
        case .bool(let v): return v ? "true" : "false"
        case .string(let v): return v
        default: return "—"
        }
    }
    static func differs(_ current: JSONValue?, _ reference: JSONValue?) -> Bool? {
        guard let current, let reference, render(current) != "—", render(reference) != "—" else { return nil }
        return render(current) != render(reference)
    }
}

/// Shared editor state. Disk persistence and runtime adoption remain separate facts.
struct PerformanceConfigurationState {
    private(set) var snapshot: [String: JSONValue] = [:]
    var edited: [String: JSONValue] = [:]
    var preview: [String: JSONValue] = [:]
    var current: [String: JSONValue] { snapshot["current"]?.object ?? [:] }
    var lastApplied: [String: JSONValue] { snapshot["last_applied"]?.object ?? [:] }
    var backup: [String: JSONValue] { snapshot["backup"]?.object ?? [:] }
    var effectiveVerified: Bool { false } // No live Guest adoption probe in this editor.
    mutating func acceptSnapshot(_ result: [String: JSONValue]) {
        snapshot = result; edited = result["draft"]?.object ?? current; preview = [:]
    }
    mutating func acceptPreview(_ result: [String: JSONValue]) {
        guard let plan = result["plan"]?.object,
              plan["revision"]?.text == snapshot["revision"]?.text,
              result["token"]?.text != nil else { preview = [:]; return }
        preview = result
    }
}
