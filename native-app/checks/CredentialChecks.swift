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
        try check(manager.status(.ssh) == .provided && manager.status(.sudo) == .provided, "one input supplies both challenges")
        let first = try manager.parameters(for: "canonical-fx|hash|pid-start|config")
        try check(first["password"]?.text == fake && first["sudo_password"]?.text == fake, "one value reaches both native challenge fields")
        await manager.authenticated(.ssh, value: fake, target: "foreign-target")
        try check(!manager.reusable(.ssh), "foreign proof rejected")
        await manager.authenticated(.ssh, value: "stale-input", target: manager.scope!)
        try check(!manager.reusable(.ssh), "stale input proof rejected")
        await manager.authenticated(.ssh, value: fake, target: manager.scope!)
        try check(manager.status(.ssh) == .verified && manager.status(.sudo) == .provided, "SSH proof never verifies sudo")
        await manager.authenticated(.sudo, value: fake, target: manager.scope!)
        try check(manager.reusable(.sudo), "actual sudo proof marks sudo verified")
        try check(try manager.parameters(for: manager.scope!).count == 2, "same-session reuse without reentry")
        manager.password = fake + "-changed"
        try check(manager.status(.ssh) == .provided && manager.status(.sudo) == .provided, "editing revokes both proofs")
        manager.reject(.sudo)
        let rejected = try manager.parameters(for: manager.scope!)
        try check(manager.status(.sudo) == .failed && rejected["sudo_password"] == nil && rejected["password"] != nil,
                  "sudo rejection suppresses sudo retry while keeping SSH usable")
        await manager.acceptSharedPassword(fake + "-changed", target: manager.scope!)
        try check(manager.status(.sudo) == .provided, "Settings confirmation enables a fresh sudo check")
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
        manager.password = fake; manager.clear()
        try check(manager.isEmpty && manager.guestBoot == nil && manager.scope == nil, "user clear invalidates all binding and authentication")
        var owned: SessionCredentialManager? = SessionCredentialManager(); weak var weakOwned = owned
        owned?.password = fake; owned = nil
        try check(weakOwned == nil, "no persistent manager owner after exit")
        let nextProcessModel = SessionCredentialManager()
        try check(nextProcessModel.isEmpty && !nextProcessModel.reusable(.ssh), "new process model cannot restore credentials")
        let rebootManager = SessionCredentialManager()
        await rebootManager.prepare(for: "fixture-reboot-target", savedTarget: "verified-fixture-disk")
        rebootManager.password = fake
        let oldBoot = UUID().uuidString, newBoot = UUID().uuidString
        try rebootManager.bindGuest(oldBoot)
        await rebootManager.authenticated(.ssh, value: fake, target: "fixture-reboot-target")
        try rebootManager.acceptExpectedReboot(from: oldBoot, to: newBoot, target: "fixture-reboot-target")
        try check(rebootManager.password == fake && rebootManager.guestBoot == newBoot && !rebootManager.reusable(.ssh), "approved reboot retains memory input while revoking old authorization")
        await rebootManager.authenticated(.ssh, value: fake, target: "fixture-reboot-target")
        let observed = UUID().uuidString
        try rebootManager.observeGuest(observed)
        try check(rebootManager.password == fake && rebootManager.guestBoot == observed && !rebootManager.reusable(.ssh),
                  "fresh proof of new boot on the same disk revokes live authorization")

        do {
            try rebootManager.acceptExpectedReboot(from: observed, to: UUID().uuidString, target: "other-target")
            try check(false, "foreign target rejected")
        } catch { try check(rebootManager.isEmpty, "foreign reboot target clears credentials") }
        let redactor = CredentialRedactor(secrets: [fake])
        try check(!redactor.text(fake + " Authorization: Bearer " + fake).contains(fake), "secret and authorization redacted")
        let nested = redactor.event(["nested": .object(["password": .string(fake)]), "items": .array([.string(fake)])])
        let sample = ["value", "not", "in", "session"].joined(separator: "-")
        let sensitiveKeys = CredentialRedactor(secrets: []).event(["nested": .object(["token": .string(sample)])])
        try check(!CoreString.encode(sensitiveKeys).contains(sample), "nested sensitive-key values are redacted even if not in session")
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
