import AppKit
import Combine
import Security
import Sparkle

enum UpdateString: String {
    case section, currentVersion, automaticChecks, checkNow, unconfigured, ready, checking
    case available, finished, failed, scope, languageRestart, automaticOff, automaticOn
    case build, channel, stable, preview, lastCheck, never, noReleases, upToDate, releaseNotes
    case downloadOnly, downloadInstall, downloading, downloaded, installing, cancelled, cancel
    case trustBlocked, previewBlocked, network, malformed, missingAsset, incompatible, signature, integrity, diskSpace, download, installFailed, remindLater
    var english: String {
        switch self {
        case .section: return "Software Update"
        case .currentVersion: return "Current App version"
        case .automaticChecks: return "Automatically check for updates"
        case .checkNow: return "Check for Updates…"
        case .unconfigured: return "Signed update service is not configured. Manual GitHub release checks are available."
        case .ready: return "Ready to check for updates"
        case .checking: return "Checking for updates…"
        case .available: return "A newer release is listed"
        case .finished: return "Update cycle finished; installation and relaunch are not confirmed."
        case .failed: return "Update failed"
        case .scope: return "Only this Launcher is updated. Game, Steam, FX Runtime, Guest and EAC are excluded."
        case .languageRestart: return "Restart the App to apply language to macOS and Sparkle menus."
        case .automaticOff: return "Automatic checks are off. Sparkle manages consent when the signed service is ready."
        case .automaticOn: return "Automatic checks are on (Sparkle preference)."
        case .build: return "Current build"
        case .channel: return "Update channel"
        case .stable: return "Stable"
        case .preview: return "Preview"
        case .lastCheck: return "Last check"
        case .never: return "Not checked"
        case .noReleases: return "No Native App release is published for this channel."
        case .upToDate: return "No newer compatible release is listed."
        case .releaseNotes: return "Release notes"
        case .downloadOnly: return "Download verified archive"
        case .downloadInstall: return "Download and install…"
        case .downloading: return "Downloading and verifying…"
        case .downloaded: return "Archive verified and cached. Nothing installed."
        case .installing: return "Installing update…"
        case .cancelled: return "Update cancelled"
        case .cancel: return "Cancel"
        case .trustBlocked: return "Installation unavailable: a published signed Appcast, trusted Ed25519 key, Developer ID build and verified distribution setup are required."
        case .previewBlocked: return "Preview is unavailable until a signed preview publishing service is configured."
        case .network: return "The update source could not be reached. Try again later."
        case .malformed: return "Release metadata is invalid. No update will be installed."
        case .missingAsset: return "The Native update manifest, signature or archive is missing."
        case .incompatible: return "This update does not support this macOS version or architecture."
        case .signature: return "Update signature verification failed. The download is not trusted."
        case .integrity: return "Update size or checksum verification failed. Nothing installed."
        case .diskSpace: return "Insufficient disk space for the update download."
        case .download: return "Download failed. The current App is unchanged."
        case .installFailed: return "Installation failed. Reopen the current App and review Sparkle details."
        case .remindLater: return "Remind me later"
        }
    }
    @MainActor func text(_ language: String) -> String { NativeLocalization.localized(english, language: language) }
}

struct UpdateConfiguration {
    let enabled: Bool
    let feed: URL?
    let publicKey: String
    let previewEnabled: Bool
    let distributionReady: Bool
    init(info: [String: Any]) {
        enabled = info["HD2UpdateServiceEnabled"] as? String == "YES"
        feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
        publicKey = info["SUPublicEDKey"] as? String ?? ""
        previewEnabled = info["HD2PreviewServiceReady"] as? String == "YES"
        distributionReady = info["HD2UpdateDistributionReady"] as? String == "YES"
    }
    var isValid: Bool {
        guard enabled, let feed, feed.scheme == "https", feed.user == nil, feed.password == nil, feed.port == nil,
              feed.host == "lsjop.github.io", feed.path == "/helldivers2-fx-launcher/updates/stable/appcast.xml",
              feed.query == nil, feed.fragment == nil, Data(base64Encoded: publicKey)?.count == 32 else { return false }
        return true
    }
    static func trustedDistribution() -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and identifier \"\(NativeReleaseService.bundleID)\""
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let flags = (info as? [String: Any])?[kSecCodeInfoFlags as String] as? NSNumber else { return false }
        return flags.uint32Value & 0x10000 != 0 // CS_RUNTIME; ad-hoc builds never enable installation.
    }
}

// Updates only the current Launcher. No Python/Core/FX or Guest update calls.
@MainActor final class AppUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = true
    @Published private(set) var automaticChecks = false
    @Published private(set) var status: UpdateString = .unconfigured
    @Published private(set) var errorCode: String?
    @Published private(set) var lastCheck: Date?
    @Published private(set) var candidate: NativeUpdateCandidate?
    @Published private(set) var cachedArchive: URL?
    @Published private(set) var channel = "stable"
    let configuration = UpdateConfiguration(info: Bundle.main.infoDictionary ?? [:])
    private var controller: SPUStandardUpdaterController!
    private var subscriptions = Set<AnyCancellable>()
    private var operation: Task<Void, Never>?
    private let preferences: UserDefaults
    var isConfigured: Bool { configuration.isValid && configuration.distributionReady && UpdateConfiguration.trustedDistribution() }
    var canDownload: Bool { candidate?.signatureVerified == true && canCheck }
    var canInstall: Bool { isConfigured && canCheck && !BridgeWorkerStatus.isActive && FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path) }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    var service: NativeReleaseService { NativeReleaseService(publicKey: Data(base64Encoded: configuration.publicKey).flatMap { $0.count == 32 ? $0 : nil }) }
    override convenience init() { self.init(preferences: .standard) }
    init(preferences: UserDefaults) {
        self.preferences = preferences
        super.init()
        lastCheck = preferences.object(forKey: "NativeUpdateLastCheck") as? Date
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        guard isConfigured else { return }
        controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] in self?.canCheck = $0 }.store(in: &subscriptions)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).sink { [weak self] in self?.automaticChecks = $0 }.store(in: &subscriptions)
        status = .ready
        controller.startUpdater() // Sparkle retains automatic-check consent ownership.
    }
    func checkForUpdates() {
        guard canCheck, operation == nil else { return }
        candidate = nil; cachedArchive = nil; errorCode = nil; status = .checking
        lastCheck = Date(); preferences.set(lastCheck, forKey: "NativeUpdateLastCheck")
        if isConfigured { controller.checkForUpdates(nil); return }
        canCheck = false
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.operation = nil; self.canCheck = true }
            do {
                let os = ProcessInfo.processInfo.operatingSystemVersion
                #if arch(arm64)
                let architecture = "arm64"
                #else
                let architecture = "x86_64"
                #endif
                let result = try await self.service.check(version: self.version, build: Int(self.build) ?? 0, channel: self.channel,
                    osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", architecture: architecture)
                try Task.checkCancellation()
                switch result {
                case .noReleases: self.status = .noReleases
                case .upToDate: self.status = .upToDate
                case .available(let candidate): self.candidate = candidate; self.status = .available
                }
            } catch { self.record(error) }
        }
    }
    func selectChannel(_ channel: String) {
        guard operation == nil, canCheck, channel == "stable" || (channel == "preview" && isConfigured && configuration.previewEnabled) else { return }
        self.channel = channel; candidate = nil; cachedArchive = nil; status = isConfigured ? .ready : .unconfigured
        if isConfigured { controller.updater.resetUpdateCycle() }
    }
    func setAutomaticChecks(_ enabled: Bool) {
        guard isConfigured else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }
    func downloadVerifiedArchive() {
        guard canDownload, let candidate, operation == nil else { return }
        canCheck = false; status = .downloading; errorCode = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.operation = nil; self.canCheck = true }
            do {
                let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Helldivers2FXLauncher/VerifiedUpdates", isDirectory: true)
                self.cachedArchive = try await self.service.download(candidate, to: base)
                self.status = .downloaded
            } catch { self.record(error) }
        }
    }
    func installWithSparkle() {
        guard canInstall else { return }
        controller.checkForUpdates(nil) // Official consent/download/signature/install UI; never install a cache ourselves.
    }
    func cancel() { operation?.cancel() }
    private func record(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { status = .cancelled; return }
        if let failure = error as? NativeUpdateFailure { status = UpdateString(rawValue: failure.rawValue) ?? .failed; errorCode = failure.rawValue }
        else { status = error is URLError ? .network : .download; errorCode = "UPDATE_OPERATION_FAILED" }
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard isConfigured else { throw NativeUpdateFailure.unconfigured }
        status = .checking; errorCode = nil
        lastCheck = Date(); preferences.set(lastCheck, forKey: "NativeUpdateLastCheck")
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { status = .available }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let value = error as NSError
        let reason = value.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber
        status = Self.noUpdateStatus(reason: reason?.intValue)
    }
    static func noUpdateStatus(reason: Int?) -> UpdateString {
        if [1,2].contains(reason ?? -1) { return .upToDate }
        if [3,4,5].contains(reason ?? -1) { return .incompatible }
        return .finished // Unknown/no items is not evidence of current-version freshness.
    }
    func recordSparkleFailure(_ error: Error) {
        let value = error as NSError
        if value.domain == SUSparkleErrorDomain {
            switch value.code {
            case 1001: status = Self.noUpdateStatus(reason: (value.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue)
            case 2000,2001: status = .download
            case 3001: status = .signature
            case 3002: status = .integrity
            case 4007: status = .cancelled
            case 4000..<5000: status = .installFailed
            default: status = .failed
            }
        } else { status = (error as? URLError)?.code == .cancelled ? .cancelled : .network }
        errorCode = value.domain + " / " + String(value.code)
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { recordSparkleFailure(error) }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error { self.updater(updater, didAbortWithError: error) }
        else if status == .checking { status = .finished }
    }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) { status = .downloading }
    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) { status = .download; errorCode = "SPARKLE_DOWNLOAD_FAILED" }
    func userDidCancelDownload(_ updater: SPUUpdater) { status = .cancelled }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { status = .installing }
    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://lsjop.github.io/helldivers2-fx-launcher/updates/" + (channel == "preview" && configuration.previewEnabled ? "preview" : "stable") + "/appcast.xml"
    }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard isConfigured, !BridgeWorkerStatus.isActive,
              FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path),
              let url = updateItem.fileURL, NativeUpdateHTTP.trusted(url), url.pathExtension == "zip",
              updateItem.installationType == "application", updateItem.isMacOsUpdate,
              let remoteBuild = Int(updateItem.versionString), let localBuild = Int(build), remoteBuild > localBuild,
              let remoteVersion = try? NativeVersion(updateItem.displayVersionString), let localVersion = try? NativeVersion(version),
              remoteVersion >= localVersion else { throw NativeUpdateFailure.incompatible }
    }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { channel == "preview" && configuration.previewEnabled ? ["preview"] : [] }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard BridgeWorkerStatus.isActive else { return false }
        Task { @MainActor in
            while BridgeWorkerStatus.isActive { try? await Task.sleep(nanoseconds: 200_000_000) }
            installHandler()
        }
        return true
    }
}
