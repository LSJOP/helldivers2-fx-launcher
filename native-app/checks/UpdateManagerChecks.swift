import Foundation

@main struct UpdateManagerChecks {
    @MainActor static func main() throws {
        var passed = 0
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw NSError(domain: message,code:1) }
            passed += 1; print("PASS " + message)
        }
        let name = "com.lsjop.update-fixture." + UUID().uuidString
        let preferences = UserDefaults(suiteName:name)!
        defer { preferences.removePersistentDomain(forName:name) }
        let manager = AppUpdateManager(preferences:preferences)
        try check(manager.canCheck && !manager.isConfigured && manager.status == .unconfigured,"manual check available while unsigned install is blocked")
        manager.setAutomaticChecks(true)
        try check(!manager.automaticChecks,"unconfigured automatic checks remain disabled")
        manager.selectChannel("preview")
        try check(manager.channel == "stable","preview remains closed without verified publishing setup")
        try check(manager.service.publicKey == nil, "empty public key remains unconfigured, never a signature failure")
        try check(!manager.canInstall && !manager.canDownload,"unsigned test bundle cannot install or download an unverified candidate")
        try check(!manager.canStartInstall && !manager.canCancelOperation, "one-click install and cancellation stay unavailable without a verified candidate or active operation")
        let valid: [String:Any] = ["HD2UpdateServiceEnabled":"YES","SUFeedURL":"https://lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml","SUPublicEDKey":Data(repeating:1,count:32).base64EncodedString()]
        try check(UpdateConfiguration(info:valid).isValid,"official HTTPS feed and correctly sized public key accepted")
        try check(UpdateConfiguration(info: valid.merging(["SUFeedURL": "https://github.com/LSJOP/helldivers2-fx-launcher/releases/latest/download/appcast.xml"]) { _, value in value }).isValid,
                  "official stable GitHub Release appcast accepted")
        let github = "https://github.com/LSJOP/helldivers2-fx-launcher/releases/latest/download/appcast.xml"
        let githubConfig = UpdateConfiguration(info: valid.merging(["SUFeedURL": github]) { _, value in value })
        try check(githubConfig.resolvedFeed(channel: "stable")?.absoluteString == github, "delegate retains configured GitHub feed")
        try check(githubConfig.resolvedFeed(channel: "preview") == nil, "unconfigured preview fails closed")
        for feed in ["http://lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml","https://evil.example/appcast.xml","https://lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml?override=1"] {
            try check(!UpdateConfiguration(info:valid.merging(["SUFeedURL":feed]) { _,new in new }).isValid,"unsafe feed rejected")
        }
        try check(!UpdateConfiguration.trustedDistribution(),"standalone test executable is not the signed launcher bundle")
        print("\(passed) update manager checks PASS")
    }
}
