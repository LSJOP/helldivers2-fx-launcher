import AppKit
import Combine
import Sparkle

enum UpdateString: String {
    case section, currentVersion, automaticChecks, checkNow, unconfigured, ready, checking
    case available, finished, failed, scope, languageRestart, automaticOff, automaticOn
    func text(_ language: String) -> String {
        let keys: [String: String] = ["section":"ui.312","currentVersion":"ui.085","automaticChecks":"ui.031","checkNow":"ui.051","unconfigured":"ui.372","ready":"ui.373","checking":"ui.056","available":"ui.015","finished":"ui.369","failed":"ui.370","scope":"ui.374","languageRestart":"ui.171","automaticOff":"ui.029","automaticOn":"ui.030"]
        return keys[rawValue].map { NativeStrings.text($0, language: language) } ?? "⟦updates." + rawValue + "⟧"
    }
}

struct UpdateConfiguration {
    let enabled: Bool
    let feed: URL?
    let publicKey: String
    init(info: [String: Any]) {
        enabled = info["HD2UpdateServiceEnabled"] as? String == "YES"
        feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
        publicKey = info["SUPublicEDKey"] as? String ?? ""
    }
    var isValid: Bool {
        guard enabled, let feed, feed.scheme == "https", feed.user == nil, feed.password == nil,
              feed.host?.lowercased() == "lsjop.github.io",
              ["/helldivers2-fx-launcher/updates/stable/appcast.xml", "/helldivers2-fx-launcher/updates/preview/appcast.xml"].contains(feed.path),
              feed.query == nil, feed.fragment == nil,
              Data(base64Encoded: publicKey)?.count == 32 else { return false }
        return true
    }
}

// Owns only the current Launcher bundle. No Python, FX or Guest update hooks.
@MainActor final class AppUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var status: UpdateString = .unconfigured
    @Published private(set) var errorCode: String?
    let configuration = UpdateConfiguration(info: Bundle.main.infoDictionary ?? [:])
    private var controller: SPUStandardUpdaterController!
    private var subscriptions = Set<AnyCancellable>()
    var isConfigured: Bool { configuration.isValid }
    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info["CFBundleVersion"] as? String ?? "?") + ")"
    }
    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        guard isConfigured else { return }
        controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] in self?.canCheck = $0 }.store(in: &subscriptions)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).sink { [weak self] in self?.automaticChecks = $0 }.store(in: &subscriptions)
        // Do not set SUEnableAutomaticChecks or override Sparkle's first-run consent.
        status = .ready
        controller.startUpdater()
    }
    func checkForUpdates() {
        guard isConfigured, canCheck else { return }
        status = .checking; errorCode = nil
        controller.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ enabled: Bool) {
        guard isConfigured else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { status = .available }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let value = error as NSError
        status = .failed; errorCode = value.domain + " / " + String(value.code)
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error { self.updater(updater, didAbortWithError: error) }
        else { status = .finished } // A closed cycle does not mean a successful installation.
    }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Bundle.main.object(forInfoDictionaryKey: "HD2UpdateChannel") as? String == "preview" ? ["preview"] : []
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard BridgeWorkerStatus.isActive else { return false }
        Task { @MainActor in
            while BridgeWorkerStatus.isActive { try? await Task.sleep(nanoseconds: 200_000_000) }
            installHandler()
        }
        return true
    }
}
