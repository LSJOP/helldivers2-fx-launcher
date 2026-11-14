import AppKit
import Combine
import Security

enum UpdateString: String {
    case section, currentVersion, automaticChecks, checkNow, unconfigured, ready, checking
    case available, finished, failed, scope, languageRestart, automaticOff, automaticOn
    case build, channel, stable, preview, lastCheck, never, noReleases, upToDate, releaseNotes
    case downloadOnly, downloadInstall, downloading, downloaded, installing, cancelled, cancel
    case trustBlocked, previewBlocked, network, malformed, missingAsset, incompatible, signature, integrity, diskSpace, download, installFailed, remindLater
    var key: String {
        switch self {
        case .section: return "ui.312"
        case .currentVersion: return "ui.085"
        case .automaticChecks: return "ui.031"
        case .checkNow: return "ui.051"
        case .unconfigured: return "ui.372"
        case .ready: return "ui.373"
        case .checking: return "ui.056"
        case .available: return "ui.015"
        case .finished: return "ui.369"
        case .failed: return "ui.370"
        case .scope: return "ui.374"
        case .languageRestart: return "ui.171"
        case .automaticOff: return "ui.029"
        case .automaticOn: return "ui.030"
        case .build: return "ui.integrated.046"
        case .channel: return "ui.integrated.047"
        case .stable: return "ui.314"
        case .preview: return "ui.232"
        case .lastCheck: return "ui.integrated.048"
        case .never: return "ui.208"
        case .noReleases: return "ui.integrated.049"
        case .upToDate: return "ui.integrated.050"
        case .releaseNotes: return "ui.integrated.051"
        case .downloadOnly: return "ui.integrated.052"
        case .downloadInstall: return "ui.integrated.053"
        case .downloading: return "ui.integrated.054"
        case .downloaded: return "ui.integrated.055"
        case .installing: return "ui.integrated.056"
        case .cancelled: return "ui.integrated.057"
        case .cancel: return "ui.037"
        case .trustBlocked: return "ui.integrated.058"
        case .previewBlocked: return "ui.integrated.059"
        case .network: return "ui.integrated.060"
        case .malformed: return "ui.integrated.061"
        case .missingAsset: return "ui.integrated.062"
        case .incompatible: return "ui.integrated.063"
        case .signature: return "ui.integrated.064"
        case .integrity: return "ui.integrated.065"
        case .diskSpace: return "ui.integrated.066"
        case .download: return "ui.integrated.067"
        case .installFailed: return "ui.integrated.068"
        case .remindLater: return "ui.integrated.069"
        }
    }
    var english: String { NativeStrings.text(key, language: "en") }
    func text(_ language: String) -> String { NativeStrings.text(key, language: language) }
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
        if Bundle.main.bundleIdentifier == NativeReleaseService.testBundleID {
            return enabled && previewEnabled && Data(base64Encoded: publicKey)?.count == 32
        }
        guard enabled, let feed, feed.scheme == "https", feed.user == nil, feed.password == nil, feed.port == nil,
              ((feed.host == "lsjop.github.io" && feed.path == "/helldivers2-fx-launcher/updates/stable/appcast.xml") ||
               (feed.host == "github.com" && feed.path == "/LSJOP/helldivers2-fx-launcher/releases/latest/download/appcast.xml")),
              feed.query == nil, feed.fragment == nil, Data(base64Encoded: publicKey)?.count == 32 else { return false }
        return true
    }
    func resolvedFeed(channel: String) -> URL? {
        guard isValid else { return nil }
        if channel == "preview" {
            guard previewEnabled else { return nil }
            return URL(string: "https://lsjop.github.io/helldivers2-fx-launcher/updates/preview/appcast.xml")
        }
        return feed
    }
    static func trustedDistribution() -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        guard let identifier = Bundle.main.bundleIdentifier,
              [NativeReleaseService.bundleID, NativeReleaseService.testBundleID].contains(identifier) else { return false }
        let rule = "identifier \"\(identifier)\""
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), requirement) == errSecSuccess else { return false }
        // Ed25519 verifies publisher authority. This gate checks local code structure.
        // Stable ad hoc builds are supported without a Developer ID requirement.
        return true
    }
}

// Updates only the current Launcher. No Python/Core/FX or Guest update calls.
@MainActor final class AppUpdateManager: NSObject, ObservableObject {
    @Published private(set) var canCheck = true
    @Published private(set) var automaticChecks = false
    @Published private(set) var status: UpdateString = .unconfigured
    @Published private(set) var errorCode: String?
    @Published private(set) var lastCheck: Date?
    @Published private(set) var candidate: NativeUpdateCandidate?
    @Published private(set) var cachedArchive: URL?
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var channel = "stable"
    let configuration = UpdateConfiguration(info: Bundle.main.infoDictionary ?? [:])
    private var operation: Task<Void, Never>?
    var canCancelOperation: Bool { operation != nil }
    private var automaticTask: Task<Void, Never>?
    private let preferences: UserDefaults
    var isConfigured: Bool { configuration.isValid && configuration.distributionReady && UpdateConfiguration.trustedDistribution() }
    var canDownload: Bool { candidate?.signatureVerified == true && cachedArchive == nil && canCheck }
    var canInstall: Bool {
        guard candidate?.manifest.schema == 2, let cachedArchive,
              FileManager.default.fileExists(atPath: cachedArchive.path),
              isConfigured, canCheck, !CoreWorkerStatus.isActive else { return false }
        return FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
    }
    var canStartInstall: Bool {
        guard candidate?.signatureVerified == true, candidate?.manifest.schema == 2,
              isConfigured, canCheck, operation == nil, !CoreWorkerStatus.isActive else { return false }
        return FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
    }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    var service: NativeReleaseService { NativeReleaseService(publicKey: Data(base64Encoded: configuration.publicKey).flatMap { $0.count == 32 ? $0 : nil }) }
    override convenience init() { self.init(preferences: .standard) }
    init(preferences: UserDefaults) {
        self.preferences = preferences
        super.init()
        if Bundle.main.bundleIdentifier == NativeReleaseService.testBundleID { channel = NativeReleaseService.testChannel }
        lastCheck = preferences.object(forKey: "NativeUpdateLastCheck") as? Date
        guard isConfigured else { return }
        status = .ready
        setAutomaticChecks(preferences.bool(forKey: "NativeAutomaticUpdateChecks"))
    }
    func checkForUpdates() {
        guard canCheck, operation == nil else { return }
        candidate = nil; cachedArchive = nil; errorCode = nil; status = .checking
        lastCheck = Date(); preferences.set(lastCheck, forKey: "NativeUpdateLastCheck")
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
        guard self.channel != NativeReleaseService.testChannel, operation == nil, canCheck, channel == "stable" || (channel == "preview" && isConfigured && configuration.previewEnabled) else { return }
        self.channel = channel; candidate = nil; cachedArchive = nil; status = isConfigured ? .ready : .unconfigured
    }
    func setAutomaticChecks(_ enabled: Bool) {
        guard isConfigured else { return }
        automaticChecks = enabled
        preferences.set(enabled, forKey: "NativeAutomaticUpdateChecks")
        automaticTask?.cancel()
        automaticTask = nil
        guard enabled else { return }
        automaticTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkForUpdates()
                do { try await Task.sleep(nanoseconds: 21_600_000_000_000) }
                catch { return }
                if self == nil { return }
            }
        }
    }
    func downloadVerifiedArchive(installAfterDownload: Bool = false) {
        guard canDownload, let candidate, operation == nil else { return }
        canCheck = false; status = .downloading; errorCode = nil; downloadProgress = nil
        operation = Task { [weak self] in
            guard let self else { return }
            var readyToInstall = false
            do {
                let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(self.channel == NativeReleaseService.testChannel ? "HD2FXNativeUpdateTest/VerifiedUpdates" : "Helldivers2FXLauncher/VerifiedUpdates", isDirectory: true)
                self.cachedArchive = try await self.service.download(candidate, to: base) { [weak self] received, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.status == .downloading, total > 0,
                              received >= 0, total == candidate.manifest.length else { return }
                        self.downloadProgress = min(1, Double(received) / Double(total))
                    }
                }
                try Task.checkCancellation()
                self.status = .downloaded
                readyToInstall = installAfterDownload
            } catch { self.record(error) }
            self.operation = nil; self.canCheck = true
            if readyToInstall { self.handoffInstallation() }
        }
    }
    func downloadAndInstall() {
        guard canStartInstall else { return }
        if cachedArchive != nil { handoffInstallation() }
        else { downloadVerifiedArchive(installAfterDownload: true) }
    }
    private func handoffInstallation() {
        guard canInstall, let candidate, let cachedArchive else { return }
        canCheck = false
        status = .installing
        errorCode = nil
        do {
            try service.verifyForInstallation(candidate, archive: cachedArchive)
            let request = cachedArchive.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: request, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            do {
                try candidate.manifestBytes.write(to: request.appendingPathComponent("manifest.json"))
                try candidate.manifestSignature.write(to: request.appendingPathComponent("manifest.sig"))
                try FileManager.default.linkItem(at: cachedArchive, to: request.appendingPathComponent("archive.zip"))
                let helper = Process()
                helper.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/HD2UpdateInstaller")
                helper.arguments = [request.path, String(ProcessInfo.processInfo.processIdentifier)]
                helper.terminationHandler = { [weak self] process in
                    try? FileManager.default.removeItem(at: request)
                    guard process.terminationStatus != 0 else { return }
                    Task { @MainActor [weak self] in
                        self?.status = .installFailed
                        self?.errorCode = "UPDATE_INSTALLER_FAILED"
                        self?.canCheck = true
                    }
                }
                try helper.run()
                Task { @MainActor [weak self] in
                    while helper.isRunning {
                        if FileManager.default.fileExists(atPath: request.appendingPathComponent("prepared").path) {
                            guard !CoreWorkerStatus.isActive else { return }
                            NSApp.terminate(nil)
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    self?.canCheck = true
                }
            } catch {
                try? FileManager.default.removeItem(at: request)
                throw error
            }
        } catch {
            record(error)
            if !(error is NativeUpdateFailure) { status = .installFailed }
            canCheck = true
        }
    }
    func cancel() { operation?.cancel() }
    private func record(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { status = .cancelled; return }
        if let failure = error as? NativeUpdateFailure { status = UpdateString(rawValue: failure.rawValue) ?? .failed; errorCode = failure.rawValue }
        else { status = error is URLError ? .network : .download; errorCode = "UPDATE_OPERATION_FAILED" }
    }
}
