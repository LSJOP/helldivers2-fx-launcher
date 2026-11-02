import Foundation
import Combine
import Security
import CryptoKit

enum CredentialKind: String, CaseIterable, Sendable {
    case ssh, sudo
    var bridgeField: String {
        switch self { case .ssh: return "password"; case .sudo: return "sudo_password" }
    }
}

enum CredentialVaultError: Error, Equatable { case locked, permission, unavailable, status(Int32) }
protocol CredentialVault: Sendable {
    func contains(_ key: String) async throws -> Bool
    func load(_ key: String, interactive: Bool) async throws -> String?
    func save(_ value: String, key: String) async throws
    func remove(_ key: String) async throws
    func removeAll() async throws
}

// The system protects encryption keys. No App-owned key or encrypted password file.
actor KeychainCredentialVault: CredentialVault {
    private let service: String
    init(service: String = "com.lsjop.helldivers2fx.native.remembered-credentials.v1") { self.service = service }
    private func query(_ key: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                              kSecAttrSynchronizable as String: false]
        if let key { q[kSecAttrAccount as String] = key }
        return q
    }
    private func failure(_ status: OSStatus) -> CredentialVaultError {
        if status == errSecNotAvailable || status == errSecNoSuchKeychain { return .unavailable }
        if status == errSecInteractionNotAllowed || status == errSecInteractionRequired || status == errSecAuthFailed || status == errSecUserCanceled {
            // This legacy login-Keychain API reports lock state without unlocking it.
            // It is used only to distinguish a locked keychain from an access/ACL issue.
            var chain: SecKeychain?; var state: SecKeychainStatus = 0
            if SecKeychainCopyDefault(&chain) == errSecSuccess, let chain,
               SecKeychainGetStatus(chain, &state) == errSecSuccess,
               state & SecKeychainStatus(kSecUnlockStateStatus) == 0 { return .locked }
            return .permission
        }
        return .status(status)
    }
    func contains(_ key: String) throws -> Bool {
        var q = query(key); q[kSecReturnAttributes as String] = true
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw failure(status) }
        return true
    }
    func load(_ key: String, interactive: Bool = false) throws -> String? {
        var q = query(key)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnData as String] = true
        q[kSecUseAuthenticationUI as String] = interactive ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure(status) }
        guard let bytes = item as? Data, let value = String(data: bytes, encoding: .utf8) else { throw CredentialVaultError.unavailable }
        return value
    }
    func save(_ value: String, key: String) throws {
        var q = query(key); q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(key)
            add[kSecValueData as String] = Data(value.utf8)
            add[kSecAttrLabel as String] = "HELLDIVERS 2 FX Launcher · " + (key.hasSuffix(".sudo") ? "Guest sudo" : "SSH")
            // Reject a locked login Keychain before an add could request an unlock UI.
            var chain: SecKeychain?; var state: SecKeychainStatus = 0
            if SecKeychainCopyDefault(&chain) == errSecSuccess, let chain,
               SecKeychainGetStatus(chain, &state) == errSecSuccess,
               state & SecKeychainStatus(kSecUnlockStateStatus) == 0 { throw CredentialVaultError.locked }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }
    func remove(_ key: String) throws {
        var q = query(key); q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemDelete(q as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    func removeAll() throws {
        var q = query(); q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemDelete(q as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
}

@MainActor final class SessionCredentialManager: ObservableObject {
    @Published var password = ""
    @Published var passphrase = ""
    @Published var sudoPassword = ""
    @Published var rememberSSH = false
    @Published var rememberSudo = false
    @Published private(set) var saved: Set<CredentialKind> = []
    @Published private(set) var rejected: Set<CredentialKind> = []
    @Published private(set) var vaultError: CredentialVaultError?
    private var scope: String?
    private var generation = UUID()
    private let vault: any CredentialVault
    private let preferences: UserDefaults
    @Published private var verified: [CredentialKind: String] = [:]
    private var attemptedLoads: Set<CredentialKind> = []
    private var storedValues: [CredentialKind: String] = [:]
    init(vault: any CredentialVault = KeychainCredentialVault(), preferences: UserDefaults = .standard) {
        self.vault = vault; self.preferences = preferences
    }
    var isEmpty: Bool { password.isEmpty && passphrase.isEmpty && sudoPassword.isEmpty }
    var redactor: CredentialRedactor { CredentialRedactor(secrets: [password,passphrase,sudoPassword] + Array(verified.values)) }
    private func key(_ kind: CredentialKind, scope: String) -> String {
        SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined() + "." + kind.rawValue
    }
    private func value(_ kind: CredentialKind) -> String { kind == .ssh ? password : sudoPassword }
    private func assign(_ text: String, _ kind: CredentialKind) { if kind == .ssh { password = text } else { sudoPassword = text } }
    private func remembers(_ kind: CredentialKind) -> Bool { kind == .ssh ? rememberSSH : rememberSudo }
    private var blocked: Set<String> {
        get { Set(preferences.stringArray(forKey: "NativeRejectedCredentialKeys") ?? []) }
        set { preferences.set(Array(newValue), forKey: "NativeRejectedCredentialKeys") }
    }
    func prepare(for target: String, interactive: Bool = false) async {
        if let scope, scope != target { clear(); self.scope = target }
        else { scope = target }
        let revision = generation
        if preferences.bool(forKey: "NativeCredentialAutoLoadDisabled") && !interactive { vaultError = .permission; return }
        for kind in CredentialKind.allCases {
            let account = key(kind, scope: target)
            if blocked.contains(account) { rejected.insert(kind); continue }
            if Set(preferences.stringArray(forKey: "NativeCredentialRememberDisabled") ?? []).contains(account) {
                if (try? await vault.contains(account)) == true { saved.insert(kind) }
                continue
            }
            if attemptedLoads.contains(kind) && !interactive { continue }
            attemptedLoads.insert(kind)
            do {
                let stored = try await vault.load(account, interactive: interactive)
                guard generation == revision, scope == target else { return }
                if let stored {
                    saved.insert(kind); storedValues[kind] = stored
                    if value(kind).isEmpty { assign(stored, kind); verified[kind] = stored }
                    if kind == .ssh { rememberSSH = true } else { rememberSudo = true }
                } else { saved.remove(kind) }
                vaultError = nil
            } catch { vaultError = error as? CredentialVaultError ?? .unavailable }
        }
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
        guard scope == target, !value.isEmpty, self.value(kind) == value else { return }
        let alreadyStored = saved.contains(kind) && storedValues[kind] == value
        verified[kind] = value; rejected.remove(kind)
        let account = key(kind, scope: target)
        guard remembers(kind) else { return }
        if alreadyStored { blocked.remove(account); return }
        let revision = generation
        do {
            try await vault.save(value, key: account)
            guard generation == revision, scope == target else { return }
            saved.insert(kind); storedValues[kind] = value; blocked.remove(account); vaultError = nil
        } catch { vaultError = error as? CredentialVaultError ?? .unavailable }
    }
    func reject(_ kind: CredentialKind) {
        guard let scope else { return }
        generation = UUID()
        if saved.contains(kind) { blocked.insert(key(kind, scope: scope)) }
        rejected.insert(kind); assign("", kind); verified.removeValue(forKey: kind)
    }
    func setRemember(_ kind: CredentialKind, _ enabled: Bool) {
        if kind == .ssh { rememberSSH = enabled } else { rememberSudo = enabled }
        guard let scope else { return }
        var disabled = Set(preferences.stringArray(forKey: "NativeCredentialRememberDisabled") ?? [])
        if enabled { disabled.remove(key(kind, scope: scope)) } else { disabled.insert(key(kind, scope: scope)) }
        preferences.set(Array(disabled), forKey: "NativeCredentialRememberDisabled")
        if enabled, reusable(kind) {
            let value = value(kind)
            Task { await authenticated(kind, value: value, target: scope) }
        }
    }
    func reusable(_ kind: CredentialKind) -> Bool { !value(kind).isEmpty && verified[kind] == value(kind) }
    func update(_ kind: CredentialKind) { generation = UUID(); attemptedLoads.insert(kind); assign("", kind); verified.removeValue(forKey: kind) }
    func remove(_ kind: CredentialKind) async {
        guard let scope else { return }
        generation = UUID(); assign("", kind); verified.removeValue(forKey: kind)
        let account = key(kind, scope: scope)
        blocked.insert(account) // Prevent reuse even if access policy rejects deletion.
        do {
            try await vault.remove(account)
            saved.remove(kind); storedValues.removeValue(forKey: kind); rejected.remove(kind); blocked.remove(account)
            if kind == .ssh { rememberSSH = false } else { rememberSudo = false }
            vaultError = nil
        } catch { vaultError = error as? CredentialVaultError ?? .unavailable }
    }
    func removeAll() async {
        preferences.set(true, forKey: "NativeCredentialAutoLoadDisabled")
        preferences.removeObject(forKey: "NativeRememberedRuntimeRoot")
        clear()
        do { try await vault.removeAll(); vaultError = nil; blocked = []; preferences.set(false, forKey: "NativeCredentialAutoLoadDisabled"); preferences.removeObject(forKey: "NativeCredentialRememberDisabled") }
        catch { vaultError = error as? CredentialVaultError ?? .unavailable }
    }
    func clear() {
        generation = UUID(); password = ""; passphrase = ""; sudoPassword = ""; scope = nil
        verified = [:]; storedValues = [:]; saved = []; rejected = []; attemptedLoads = []
        rememberSSH = false; rememberSudo = false; vaultError = nil
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
