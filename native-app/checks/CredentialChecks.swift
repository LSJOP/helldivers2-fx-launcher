import Foundation

actor FixtureCredentialVault: CredentialVault {
    var values: [String: String] = [:]
    var fault: CredentialVaultError?
    var interactions: [Bool] = []
    func contains(_ key: String) throws -> Bool { if let fault { throw fault }; return values[key] != nil }
    func load(_ key: String, interactive: Bool) throws -> String? { interactions.append(interactive); if let fault { throw fault }; return values[key] }
    func save(_ value: String, key: String) throws { if let fault { throw fault }; values[key] = value }
    func remove(_ key: String) throws { if let fault { throw fault }; values.removeValue(forKey: key) }
    func removeAll() throws { if let fault { throw fault }; values = [:] }
    func count() -> Int { values.count }
    func setFault(_ fault: CredentialVaultError?) { self.fault = fault }
}

@main struct CredentialChecks {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1].hasPrefix("--keychain-") {
            let vault = KeychainCredentialVault(service: "com.lsjop.helldivers2fx.credential-test." + CommandLine.arguments[2])
            let fake = "fixture-" + String(repeating: "q", count: 30)
            do {
                if CommandLine.arguments[1] == "--keychain-write" { try await vault.save(fake, key: "fictional.ssh") }
                else if CommandLine.arguments[1] == "--keychain-read" {
                    guard try await vault.load("fictional.ssh", interactive: false) == fake else { throw ErrorState("KEYCHAIN_RESTART_CHECK_FAILED") }
                } else { try await vault.removeAll() }
                print("Fictional Keychain " + CommandLine.arguments[1] + ": PASS")
            } catch { print("Fictional Keychain check unavailable: " + String(describing: error as? CredentialVaultError ?? .unavailable)); exit(2) }
            return
        }
        var passed = 0
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw ErrorState("ASSERTION_FAILED",method:name) }
            passed += 1; print("PASS " + name)
        }
        let fake = String(repeating:"m",count:24)
        var manager: SessionCredentialManager? = SessionCredentialManager()
        weak var weakManager = manager
        manager?.password = fake; manager?.passphrase = fake + "p"; manager?.sudoPassword = fake + "s"
        let first = try manager!.parameters(for:"target-a")
        try check(first.count == 3 && first["password"]?.text == fake,"three credentials are available in memory")
        try check(try manager!.parameters(for:"target-a").count == 3,"credentials reused in the same target session")
        do { _ = try manager!.parameters(for:"target-b"); throw ErrorState("EXPECTED_SCOPE_FAILURE") }
        catch let error as ErrorState { try check(error.code == "CREDENTIAL_SCOPE_CHANGED" && manager!.isEmpty,"target changes clear credentials before transmission") }
        manager?.password = fake; manager?.clear()
        try check(manager!.isEmpty,"explicit clear removes all fields")
        manager = nil
        try check(weakManager == nil,"session manager is released without a persistent owner")
        let redactor = CredentialRedactor(secrets:[fake])
        let privateText = "-----BEGIN " + "PRIVATE KEY-----\n" + String(repeating:"A",count:80) + "\n-----END PRIVATE KEY-----"
        let text = redactor.text(fake + "\nAuthorization: Bearer " + fake + "\n" + privateText)
        try check(!text.contains(fake) && !text.contains("BEGIN PRIVATE"),"known credentials, authorization and private-key bodies are redacted")
        let details=redactor.diagnostic(["summary":.string(fake),"password":.string(fake)])
        try check(details["summary"]?.text == "[REDACTED]" && details["password"]?.text == "[REDACTED]","error summaries and sensitive fields are redacted")
        let generic=CredentialRedactor(secrets:[]).text("{\"password\":\"" + fake + "\"}")
        try check(!generic.contains(fake),"quoted JSON credential diagnostics are redacted without a registered value")
        let authorization=CredentialRedactor(secrets:[]).text("{\"Authorization\":\"Bearer " + fake + "\"}")
        try check(!authorization.contains(fake),"quoted authorization diagnostics are redacted")
        let domain = "hd2-credential-fixture-" + UUID().uuidString
        let prefs = UserDefaults(suiteName: domain)!
        defer { prefs.removePersistentDomain(forName: domain) }
        let vault = FixtureCredentialVault()
        let firstManager = SessionCredentialManager(vault: vault, preferences: prefs)
        await firstManager.prepare(for: "fixture-target")
        firstManager.password = fake; firstManager.sudoPassword = fake + "s"
        await firstManager.authenticated(.ssh, value: fake, target: "fixture-target")
        await firstManager.authenticated(.sudo, value: fake + "s", target: "fixture-target")
        try check(await vault.count() == 0 && firstManager.reusable(.ssh), "unchecked remember keeps authenticated credentials in session only")
        firstManager.rememberSSH = true
        await firstManager.authenticated(.ssh, value: fake + "stale", target: "fixture-target")
        try check(await vault.count() == 0, "stale authentication proof cannot save a different input")
        await firstManager.authenticated(.ssh, value: fake, target: "fixture-target")
        try check(await vault.count() == 1, "only the opted-in verified SSH credential is saved")
        let second = SessionCredentialManager(vault: vault, preferences: prefs)
        await second.prepare(for: "fixture-target")
        try check(second.password == fake && second.sudoPassword.isEmpty && second.rememberSSH, "new App-session manager automatically loads the independent saved SSH credential")
        second.sudoPassword = fake + "s"; second.rememberSudo = true
        await second.authenticated(.sudo, value: fake + "s", target: "fixture-target")
        try check(await vault.count() == 2, "sudo uses its own independently saved credential")
        second.reject(.ssh)
        let third = SessionCredentialManager(vault: vault, preferences: prefs)
        await third.prepare(for: "fixture-target")
        try check(third.password.isEmpty && third.rejected.contains(.ssh) && third.sudoPassword == fake + "s", "rejected SSH credentials stop reuse across restarts without affecting sudo")
        third.password = fake + "v2"
        await third.authenticated(.ssh, value: fake + "v2", target: "fixture-target")
        let stillRejected = SessionCredentialManager(vault: vault, preferences: prefs)
        await stillRejected.prepare(for: "fixture-target")
        try check(stillRejected.password.isEmpty && stillRejected.rejected.contains(.ssh), "session-only correction cannot re-enable an unchanged invalid saved password")
        third.rememberSSH = true
        await third.authenticated(.ssh, value: fake + "v2", target: "fixture-target")
        let fourth = SessionCredentialManager(vault: vault, preferences: prefs)
        await fourth.prepare(for: "fixture-target")
        try check(fourth.password == fake + "v2", "successful replacement authentication updates the saved password")
        fourth.setRemember(.ssh, false)
        let disabled = SessionCredentialManager(vault: vault, preferences: prefs)
        await disabled.prepare(for: "fixture-target")
        try check(disabled.password.isEmpty && disabled.saved.contains(.ssh) && !disabled.rememberSSH, "unchecking remember disables automatic reuse while preserving the explicitly clearable item")
        await fourth.remove(.ssh)
        let fifth = SessionCredentialManager(vault: vault, preferences: prefs)
        await fifth.prepare(for: "fixture-target")
        try check(fifth.password.isEmpty && fifth.sudoPassword == fake + "s", "clearing SSH removes both its saved and session values without clearing sudo")
        await vault.setFault(.permission)
        await fifth.removeAll()
        let failedClear = SessionCredentialManager(vault: vault, preferences: prefs)
        await failedClear.prepare(for: "fixture-target")
        let retainedCount = await vault.count()
        try check(failedClear.isEmpty && retainedCount > 0, "failed deletion stops automatic reuse and does not claim old items are removed")
        await vault.setFault(nil)
        await fifth.removeAll()
        let sixth = SessionCredentialManager(vault: vault, preferences: prefs)
        await sixth.prepare(for: "fixture-target")
        let afterClear = await vault.count()
        try check(sixth.isEmpty && afterClear == 0, "clear all prevents subsequent reuse")
        let prefData = try PropertyListSerialization.data(fromPropertyList: prefs.persistentDomain(forName: domain) ?? [:], format: .xml, options: 0)
        try check(!String(decoding: prefData, as: UTF8.self).contains(fake), "preferences contain no raw password")
        await vault.setFault(.locked)
        let locked = SessionCredentialManager(vault: vault, preferences: prefs)
        await locked.prepare(for: "fixture-locked")
        try check(locked.vaultError == .locked && locked.isEmpty, "locked Keychain is reported without a plaintext fallback")
        try check(!(await vault.interactions).contains(true), "automatic reads never request authorization UI")
        locked.password = fake; locked.rememberSSH = true
        await locked.authenticated(.ssh, value: fake, target: "fixture-locked")
        try check(locked.password == fake && locked.saved.isEmpty, "unavailable secure storage preserves session use without claiming persistence")
        print("\(passed) credential checks PASS")
    }
}
