import Foundation
import Combine

enum CredentialKind: String, CaseIterable, Sendable {
    case ssh, sudo
    var bridgeField: String {
        switch self { case .ssh: return "password"; case .sudo: return "sudo_password" }
    }
}

/// Credentials never leave this process except through controlled SSH stdin/PTY.
@MainActor final class SessionCredentialManager: ObservableObject {
    @Published var password = ""
    @Published var passphrase = ""
    @Published var sudoPassword = ""
    @Published private(set) var rejected: Set<CredentialKind> = []
    private var scope: String?
    private var verified: [CredentialKind: String] = [:]
    var isEmpty: Bool { password.isEmpty && passphrase.isEmpty && sudoPassword.isEmpty }
    var redactor: CredentialRedactor { CredentialRedactor(secrets: [password, passphrase, sudoPassword] + Array(verified.values)) }
    func prepare(for target: String, interactive: Bool = false) async {
        if let scope, scope != target { clear() }
        scope = target
    }
    func parameters(for target: String) throws -> [String: JSONValue] {
        if let scope, scope != target { clear(); throw ErrorState("CREDENTIAL_SCOPE_CHANGED") }
        scope = target
        var result: [String: JSONValue] = [:]
        if !password.isEmpty { result["password"] = .string(password) }
        if !passphrase.isEmpty { result["passphrase"] = .string(passphrase) }
        if !sudoPassword.isEmpty { result["sudo_password"] = .string(sudoPassword) }
        return result
    }
    func authenticated(_ kind: CredentialKind, value: String, target: String) async {
        guard scope == target, !value.isEmpty, (kind == .ssh ? password : sudoPassword) == value else { return }
        verified[kind] = value; rejected.remove(kind)
    }
    func reject(_ kind: CredentialKind) { rejected.insert(kind); update(kind) }
    func reusable(_ kind: CredentialKind) -> Bool {
        let value = kind == .ssh ? password : sudoPassword
        return !value.isEmpty && verified[kind] == value
    }
    func update(_ kind: CredentialKind) {
        if kind == .ssh { password = ""; passphrase = "" } else { sudoPassword = "" }
        verified.removeValue(forKey: kind)
    }
    func remove(_ kind: CredentialKind) async { update(kind); rejected.remove(kind) }
    func removeAll() async { clear() }
    func clear() { password = ""; passphrase = ""; sudoPassword = ""; scope = nil; verified = [:]; rejected = [] }
}

struct CredentialRedactor: Sendable {
    let secrets: [String]
    func text(_ input: String) -> String {
        var value = input
        for secret in secrets.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            value = value.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        for pattern in [
            "(?s)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|$)",
            "(?im)(authorization[\\\"']?\\s*[:=]\\s*)[^\\r\\n]+",
            "(?i)((?:password|passphrase|sudo_password|private[_-]?key|api[_-]?key|access[_-]?token|token|client[_-]?secret)[\\\"']?\\s*[:=]\\s*)(?:\\\"[^\\\"]*\\\"|'[^']*'|[^\\s,;}]+)",
            "(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})",
            "(?i)(https?://)[^\\s/@:]+:[^\\s/@]+@"
        ] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            value = regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "[REDACTED]")
        }
        return value
    }
    func event(_ input: [String: JSONValue]) -> [String: JSONValue] {
        input.mapValues { value in
            if let string = value.text { return .string(text(string)) }
            return value
        }
    }
    func diagnostic(_ input: [String: JSONValue]) -> [String: JSONValue] {
        var result = input
        for key in ["summary", "stderr", "stdout", "message"] {
            if let value = input[key]?.text { result[key] = .string(text(value)) }
        }
        for key in input.keys where ["password", "passphrase", "sudo_password", "token", "authorization", "private_key"].contains(key.lowercased()) {
            result[key] = .string("[REDACTED]")
        }
        if let change = input["change"], containsSecret(change) {
            result.removeValue(forKey: "change")
            result["summary"] = .string("[REDACTED]")
        }
        return result
    }
    func containsSecret(_ value: JSONValue) -> Bool {
        switch value {
        case .string(let text):
            return secrets.contains(where: { $0.count >= 4 && text.contains($0) }) || CredentialRedactor(secrets: []).text(text) != text
        case .array(let items): return items.contains(where: containsSecret)
        case .object(let object): return object.values.contains(where: containsSecret)
        default: return false
        }
    }
}
