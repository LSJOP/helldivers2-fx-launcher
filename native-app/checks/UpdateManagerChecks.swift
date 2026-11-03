import Foundation
import Sparkle

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
        for (code,status) in [(2001,UpdateString.download),(3001,.signature),(3002,.integrity),(4001,.installFailed),(4005,.installFailed),(4007,.cancelled),(4012,.installFailed)] {
            manager.recordSparkleFailure(NSError(domain:SUSparkleErrorDomain,code:code))
            try check(manager.status == status,"actual Sparkle error maps to honest state: " + String(code))
        }
        try check(AppUpdateManager.noUpdateStatus(reason:1) == .upToDate && AppUpdateManager.noUpdateStatus(reason:2) == .upToDate,"up-to-date requires a known Sparkle version reason")
        try check(AppUpdateManager.noUpdateStatus(reason:3) == .incompatible,"OS incompatibility is separate from no update")
        try check(AppUpdateManager.noUpdateStatus(reason:nil) == .finished,"unknown no-update cycle is not up to date or installation success")
        let valid: [String:Any] = ["HD2UpdateServiceEnabled":"YES","SUFeedURL":"https://lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml","SUPublicEDKey":Data(repeating:1,count:32).base64EncodedString()]
        try check(UpdateConfiguration(info:valid).isValid,"official HTTPS feed and correctly sized public key accepted")
        for feed in ["http://lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml","https://evil.example/appcast.xml","https://lsjop.github.io/helldivers2-fx-launcher/updates/stable/appcast.xml?override=1"] {
            try check(!UpdateConfiguration(info:valid.merging(["SUFeedURL":feed]) { _,new in new }).isValid,"unsafe feed rejected")
        }
        try check(!UpdateConfiguration.trustedDistribution(),"local test executable is never a Developer ID distribution")
        print("\(passed) update manager checks PASS")
    }
}
