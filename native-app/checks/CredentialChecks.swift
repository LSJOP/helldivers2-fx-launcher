import Foundation

@main struct CredentialChecks {
    @MainActor static func main() throws {
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw ErrorState("ASSERTION_FAILED",method:name) }
            print("PASS " + name)
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
        print("9 credential checks PASS")
    }
}
