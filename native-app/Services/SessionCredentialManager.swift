import Foundation
import Combine

enum CredentialKind: String, CaseIterable, Sendable {
    case ssh, sudo
    var bridgeField: String {
        switch self { case .ssh: return "password"; case .sudo: return "sudo_password" }
    }
}

enum SessionCredentialStatus: String { case notProvided, provided, verified, failed }

/// One owner for live credentials; optional installation-local encrypted persistence.
/// Clearing releases references; Swift String cannot promise physical-memory erasure.
@MainActor final class SessionCredentialManager: ObservableObject {
    private let store: SavedCredentialStore?
    private var savedTarget: String?
    var hasPersistenceTarget: Bool { savedTarget != nil }
    private var restoredKinds: Set<CredentialKind> = []
    @Published private(set) var saved: Set<CredentialKind> = []
    @Published private(set) var storageIssue = false
    private var storageFailures: Set<CredentialKind> = []
    private func storageResult(_ kind: CredentialKind, failed: Bool) {
        if failed { storageFailures.insert(kind) } else { storageFailures.remove(kind) }
        storageIssue = !storageFailures.isEmpty
    }
    init(store: SavedCredentialStore? = nil) { self.store = store }
    @Published var password = "" { didSet { if oldValue != password { changed(.ssh) } } }
    @Published var passphrase = "" { didSet { if oldValue != passphrase { changed(.ssh) } } }
    @Published var sudoPassword = "" { didSet { if oldValue != sudoPassword { changed(.sudo) } } }
    @Published private(set) var rejected: Set<CredentialKind> = []
    @Published private var verified: Set<CredentialKind> = []
    private(set) var scope: String?
    private(set) var guestBoot: String?
    var isEmpty: Bool { password.isEmpty && passphrase.isEmpty && sudoPassword.isEmpty }
    var redactor: CredentialRedactor { CredentialRedactor(secrets: [password, passphrase, sudoPassword]) }
    private func changed(_ kind: CredentialKind) { verified.remove(kind); rejected.remove(kind); saved.remove(kind) }
    private func value(_ kind: CredentialKind) -> String { kind == .ssh ? password : sudoPassword }
    func status(_ kind: CredentialKind) -> SessionCredentialStatus {
        if rejected.contains(kind) { return .failed }
        if reusable(kind) { return .verified }
        return value(kind).isEmpty && !(kind == .ssh && !passphrase.isEmpty) ? .notProvided : .provided
    }
    func prepare(for target: String, savedTarget: String? = nil) async {
        if let scope, scope != target || (self.savedTarget != nil && self.savedTarget != savedTarget) { clear() }
        scope = target; self.savedTarget = savedTarget
        guard let store, let savedTarget else { return }
        for kind in CredentialKind.allCases where !restoredKinds.contains(kind) {
            do {
                if let value = try store.load(scope: savedTarget, kind: kind) {
                    if self.value(kind).isEmpty {
                        if kind == .ssh { password = value } else { sudoPassword = value }
                        saved.insert(kind)
                    }
                }
                restoredKinds.insert(kind)
                storageResult(kind, failed: false)
            } catch { storageResult(kind, failed: true) }
        }
    }
    func bindGuest(_ boot: String?) throws {
        if let guestBoot, boot != guestBoot {
            clear(); throw ErrorState("CREDENTIAL_SCOPE_CHANGED")
        }
        if let boot { guestBoot = boot }
    }
    /// Called only for the configuration reply of a user-approved, identity-verified reboot.
    /// Retains process-memory input while revoking all old live authorization.
    func acceptExpectedReboot(from old: String, to new: String, target: String, reboundTarget: String? = nil) throws {
        guard scope == target, guestBoot == old, old != new, UUID(uuidString: new) != nil else {
            clear(); throw ErrorState("CREDENTIAL_SCOPE_CHANGED")
        }
        verified = []; guestBoot = new
        if let reboundTarget { scope = reboundTarget }
    }
    func parameters(for target: String) throws -> [String: JSONValue] {
        if let scope, scope != target { clear(); throw ErrorState("CREDENTIAL_SCOPE_CHANGED") }
        scope = target
        var result: [String: JSONValue] = [:]
        if !password.isEmpty { result["password"] = .string(password) }
        if !passphrase.isEmpty { result["passphrase"] = .string(passphrase) }
        if !sudoPassword.isEmpty { result["sudo_password"] = .string(sudoPassword) }
        if let guestBoot { result["credential_guest_boot"] = .string(guestBoot) }
        return result
    }
    func authenticated(_ kind: CredentialKind, value: String, target: String) async {
        guard scope == target, !value.isEmpty, self.value(kind) == value else { return }
        verified.insert(kind); rejected.remove(kind)
        if !saved.contains(kind), let store, let savedTarget {
            do { try store.save(value, scope: savedTarget, kind: kind); saved.insert(kind); storageResult(kind, failed: false) }
            catch { storageResult(kind, failed: true) }
        }
    }
    func acceptSharedPassword(_ value: String, target: String) async {
        guard scope == target, !value.isEmpty else { return }
        password = value
        sudoPassword = value
        await authenticated(.ssh, value: value, target: target)
        if let store, let savedTarget {
            do {
                try store.save(value, scope: savedTarget, kind: .sudo)
                saved.insert(.sudo)
                storageResult(.sudo, failed: false)
            } catch { storageResult(.sudo, failed: true) }
        }
    }
    /// Copy only on explicit user action; sudo still requires its own authentication.
    func useSSHPasswordForSudo() {
        guard !password.isEmpty else { return }
        sudoPassword = password
    }
    func reusable(_ kind: CredentialKind) -> Bool { !value(kind).isEmpty && verified.contains(kind) }
    func reject(_ kind: CredentialKind) {
        update(kind); rejected.insert(kind)
    }
    func update(_ kind: CredentialKind) {
        restoredKinds.insert(kind) // Never reload a rejected or forgotten credential in this session.
        if let store, let savedTarget {
            do { try store.remove(scope: savedTarget, kind: kind); storageResult(kind, failed: false) }
            catch { storageResult(kind, failed: true) }
        }
        saved.remove(kind)
        if kind == .ssh { password = ""; passphrase = "" } else { sudoPassword = "" }
        verified.remove(kind); rejected.remove(kind)
    }
    func forgetSaved() {
        for kind in CredentialKind.allCases { update(kind) }
        clear()
    }
    func clear() {
        password = ""; passphrase = ""; sudoPassword = ""
        verified = []; rejected = []; scope = nil; guestBoot = nil; savedTarget = nil; restoredKinds = []; saved = []
    }
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
    private func scrub(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let value): return .string(text(value))
        case .object(let value): return .object(event(value))
        case .array(let values): return .array(values.map(scrub))
        default: return value
        }
    }
    func event(_ input: [String: JSONValue]) -> [String: JSONValue] {
        input.reduce(into: [:]) { result, entry in
            let sensitive = ["password", "passphrase", "sudo_password", "token", "authorization", "private_key", "access_token", "client_secret"].contains(entry.key.lowercased())
            result[entry.key] = sensitive ? .string("[REDACTED]") : scrub(entry.value)
        }
    }
    func diagnostic(_ input: [String: JSONValue]) -> [String: JSONValue] {
        var result = event(input)
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
