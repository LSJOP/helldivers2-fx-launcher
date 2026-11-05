import Foundation

@main struct CredentialChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw ErrorState("ASSERTION_FAILED", method: name) }
            count += 1; print("PASS " + name)
        }
        let fake = "fixture-memory-credential"
        let manager = SessionCredentialManager()
        try check(manager.isEmpty, "launch is empty")
        try check(manager.status(.ssh) == .notProvided && manager.status(.sudo) == .notProvided, "independent absent states")
        await manager.prepare(for: "canonical-fx|hash|pid-start|config")
        manager.password = fake
        try check(manager.status(.ssh) == .provided && manager.status(.sudo) == .notProvided, "input is provided, not verified")
        manager.sudoPassword = fake + "-sudo"
        try check(manager.status(.sudo) == .provided, "sudo input is independent")
        let first = try manager.parameters(for: "canonical-fx|hash|pid-start|config")
        try check(first["password"]?.text == fake && first["sudo_password"]?.text == fake + "-sudo", "separate fields reach native core")
        await manager.authenticated(.ssh, value: fake, target: "foreign-target")
        try check(!manager.reusable(.ssh), "foreign proof rejected")
        await manager.authenticated(.ssh, value: "stale-input", target: manager.scope!)
        try check(!manager.reusable(.ssh), "stale input proof rejected")
        await manager.authenticated(.ssh, value: fake, target: manager.scope!)
        try check(manager.status(.ssh) == .verified && manager.status(.sudo) == .provided, "SSH proof never verifies sudo")
        await manager.authenticated(.sudo, value: fake + "-sudo", target: manager.scope!)
        try check(manager.reusable(.sudo), "actual sudo proof marks sudo verified")
        try check(try manager.parameters(for: manager.scope!).count == 2, "same-session reuse without reentry")
        manager.password = fake + "-changed"
        try check(manager.status(.ssh) == .provided && manager.reusable(.sudo), "editing invalidates only that role")
        manager.reject(.sudo)
        try check(manager.status(.sudo) == .failed && manager.sudoPassword.isEmpty, "rejected credential stops reuse")
        manager.sudoPassword = fake + "-retry"
        try check(manager.status(.sudo) == .provided, "fresh input can retry without infinite automatic retry")
        try manager.bindGuest("boot-a")
        try check(try manager.parameters(for: manager.scope!)["credential_guest_boot"]?.text == "boot-a", "verified boot bound to request")
        do { try manager.bindGuest("boot-b"); throw ErrorState("EXPECTED_FAILURE") }
        catch let e as ErrorState { try check(e.code == "CREDENTIAL_SCOPE_CHANGED" && manager.isEmpty, "changed Guest clears before reuse") }
        await manager.prepare(for: "target-a"); manager.password = fake
        try manager.bindGuest("known-boot")
        do { try manager.bindGuest(nil); throw ErrorState("EXPECTED_FAILURE") }
        catch let e as ErrorState { try check(e.code == "CREDENTIAL_SCOPE_CHANGED" && manager.isEmpty, "unverifiable previously bound Guest clears credentials") }
        await manager.prepare(for: "target-a"); manager.password = fake
        await manager.prepare(for: "target-b")
        try check(manager.isEmpty, "FX identity change clears input")
        manager.password = fake
        do { _ = try manager.parameters(for: "target-c"); throw ErrorState("EXPECTED_FAILURE") }
        catch let e as ErrorState { try check(e.code == "CREDENTIAL_SCOPE_CHANGED" && manager.isEmpty, "scope mismatch blocks transmission") }
        manager.password = fake; manager.sudoPassword = fake + "s"; manager.clear()
        try check(manager.isEmpty && manager.guestBoot == nil && manager.scope == nil, "user clear invalidates all binding and authentication")
        var owned: SessionCredentialManager? = SessionCredentialManager(); weak var weakOwned = owned
        owned?.password = fake; owned = nil
        try check(weakOwned == nil, "no persistent manager owner after exit")
        let nextProcessModel = SessionCredentialManager()
        try check(nextProcessModel.isEmpty && !nextProcessModel.reusable(.ssh), "new process model cannot restore credentials")
        let rebootManager = SessionCredentialManager()
        await rebootManager.prepare(for: "fixture-reboot-target")
        rebootManager.password = fake; rebootManager.sudoPassword = fake
        let oldBoot = UUID().uuidString, newBoot = UUID().uuidString
        try rebootManager.bindGuest(oldBoot)
        await rebootManager.authenticated(.ssh, value: fake, target: "fixture-reboot-target")
        try rebootManager.acceptExpectedReboot(from: oldBoot, to: newBoot, target: "fixture-reboot-target")
        try check(rebootManager.password == fake && rebootManager.guestBoot == newBoot && !rebootManager.reusable(.ssh), "approved reboot retains memory input while revoking old authorization")
        do {
            try rebootManager.acceptExpectedReboot(from: newBoot, to: UUID().uuidString, target: "other-target")
            try check(false, "foreign target rejected")
        } catch { try check(rebootManager.isEmpty, "foreign reboot target clears credentials") }
        let redactor = CredentialRedactor(secrets: [fake])
        try check(!redactor.text(fake + " Authorization: Bearer " + fake).contains(fake), "secret and authorization redacted")
        let nested = redactor.event(["nested": .object(["password": .string(fake)]), "items": .array([.string(fake)])])
        try check(!CoreString.encode(nested).contains(fake), "nested event redaction")
        try check(!CoreString.encode(redactor.diagnostic(["other": .object(["secret": .string(fake)])])).contains(fake), "nested diagnostic redaction")
        try check(!CredentialRedactor(secrets: []).text("{\"password\":\"" + fake + "\"}").contains(fake), "unregistered structured password redaction")
        print("\(count) session credential checks PASS (persistence disabled in these fixtures)")
    }
}
// Keep this executable independent of Native Core for the service-layer checks.
private enum CoreString {
 static func encode(_ value: [String: JSONValue]) -> String { String(decoding: (try? JSONEncoder().encode(value)) ?? Data(), as: UTF8.self) }
}
