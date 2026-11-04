import Foundation
@main struct CredentialChecks {
    @MainActor static func main() async throws {
        var n = 0
        func check(_ v: Bool, _ name: String) throws { guard v else { throw ErrorState("ASSERTION_FAILED", method: name) }; n += 1; print("PASS " + name) }
        let manager = SessionCredentialManager()
        await manager.prepare(for: "fixture-a")
        manager.password = "fixture-ssh"; manager.sudoPassword = "fixture-sudo"
        try check(try manager.parameters(for: "fixture-a")["password"]?.text == "fixture-ssh", "SSH memory value")
        try check(try manager.parameters(for: "fixture-a")["sudo_password"]?.text == "fixture-sudo", "sudo independent value")
        await manager.authenticated(.ssh, value: "fixture-ssh", target: "fixture-a")
        try check(manager.reusable(.ssh) && !manager.reusable(.sudo), "SSH proof never authenticates sudo")
        manager.reject(.sudo)
        try check(manager.sudoPassword.isEmpty && !manager.password.isEmpty, "sudo rejection preserves SSH")
        try check(manager.redactor.text("fixture-ssh") == "[REDACTED]", "memory secret redacted")
        await manager.prepare(for: "fixture-b")
        try check(manager.isEmpty, "target change clears all roles")
        manager.password = "fixture-ssh"
        do { _ = try manager.parameters(for: "fixture-c"); throw ErrorState("ASSERTION_FAILED") } catch let e as ErrorState { try check(e.code == "CREDENTIAL_SCOPE_CHANGED", "stale credentials rejected") }
        try check(manager.isEmpty, "stale scope cleared")
        let restarted = SessionCredentialManager(); await restarted.prepare(for: "fixture-a")
        try check(restarted.isEmpty, "new process manager has no remembered secrets")
        manager.password = "fixture-ssh"; manager.clear(); try check(manager.isEmpty, "explicit clear")
        print("\(n) credential checks passed; no Keychain API exists")
    }
}
