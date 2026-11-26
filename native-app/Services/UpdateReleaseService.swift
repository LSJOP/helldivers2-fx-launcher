import Foundation
import CryptoKit
import Darwin
import OSLog
import Security

struct NativeRelease: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: URL; let size: Int64 }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let html_url: URL
    let body: String?
    let assets: [Asset]
}

struct NativeUpdateManifest: Codable {
    let schema: Int
    let bundleID: String
    let version: String
    let build: Int
    let channel: String
    let platform: String
    let architecture: String
    let minimumSystemVersion: String
    let archive: String
    let length: Int64
    let sha256: String
    let archiveEdSignature: String?
    let sourceCommit: String?
    let components: ComponentUpdate?
}

enum NativeUpdateFailure: String, Error {
    case network, malformed, missingAsset, incompatible, signature, unconfigured, integrity, diskSpace, download, cancelled
}

struct NativeVersion: Comparable {
    let parts: [Int]
    let prerelease: [String]
    init(_ value: String) throws {
        guard value.range(of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$"#, options: .regularExpression) != nil else { throw NativeUpdateFailure.malformed }
        let split = value.split(separator: "-", maxSplits: 1)
        parts = try split[0].split(separator: ".").map { guard let n = Int($0) else { throw NativeUpdateFailure.malformed }; return n }
        prerelease = split.count == 2 ? split[1].split(separator: ".").map(String.init) : []
        for item in prerelease where item.allSatisfy(\.isNumber) && item.count > 1 && item.first == "0" { throw NativeUpdateFailure.malformed }
    }
    static func < (a: Self, b: Self) -> Bool {
        if a.parts != b.parts { return a.parts.lexicographicallyPrecedes(b.parts) }
        if a.prerelease.isEmpty || b.prerelease.isEmpty { return !a.prerelease.isEmpty && b.prerelease.isEmpty }
        for (left,right) in zip(a.prerelease,b.prerelease) where left != right {
            let ln = left.allSatisfy(\.isNumber), rn = right.allSatisfy(\.isNumber)
            if ln && rn { return left.count == right.count ? left < right : left.count < right.count }
            if ln != rn { return ln }
            return left < right
        }
        return a.prerelease.count < b.prerelease.count
    }
}

struct NativeUpdateCandidate {
    let release: NativeRelease
    let manifest: NativeUpdateManifest
    let archive: NativeRelease.Asset
    let signatureVerified: Bool
    let manifestBytes: Data
    let manifestSignature: Data
}

enum NativeReleaseResult {
    case noReleases, upToDate, available(NativeUpdateCandidate)
}

protocol NativeUpdateTransport {
    func data(from url: URL, limit: Int) async throws -> Data
    func download(from url: URL, limit: Int64) async throws -> URL
    func download(from url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL
}

extension NativeUpdateTransport {
    func download(from url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        try await download(from: url, limit: limit)
    }
}

/// Only public GitHub API/release endpoints; credentials and cookies are never used.
final class NativeUpdateHTTP: NSObject, NativeUpdateTransport, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    static let repository = "LSJOP/helldivers2-fx-launcher"
    private let limit: Int64
    private let progress: @Sendable (Int64, Int64) -> Void
    init(limit: Int64 = NativeReleaseService.maximumArchiveBytes, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) {
        self.limit = limit; self.progress = progress
    }
    static func trusted(_ url: URL, redirect: Bool = false) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil, url.fragment == nil else { return false }
        if redirect && url.host == "release-assets.githubusercontent.com" { return true }
        if url.host == "api.github.com" {
            guard url.path == "/repos/\(repository)/releases" else { return false }
            if url.query == nil { return true }
            return (1...5).contains { url.query == "per_page=100&page=\($0)" }
        }
        guard url.query == nil else { return false }
        return url.host == "github.com" && (url.path.hasPrefix("/\(repository)/releases/download/v") || url.path.hasPrefix("/\(repository)/releases/download/native-v"))
    }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 600
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    private func request(_ url: URL) throws -> URLRequest {
        guard Self.trusted(url) else { throw NativeUpdateFailure.malformed }
        var request = URLRequest(url: url)
        request.setValue("HD2FXNative-UpdateCheck/1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }
    private func validate(_ response: URLResponse, limit: Int64) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let url = response.url, Self.trusted(url, redirect: true) else { throw NativeUpdateFailure.network }
        guard response.expectedContentLength <= limit else { throw NativeUpdateFailure.malformed }
    }
    func data(from url: URL, limit: Int) async throws -> Data {
        let session = session(); defer { session.invalidateAndCancel() }
        let (bytes,response) = try await session.bytes(for: request(url))
        try validate(response, limit: Int64(limit))
        var result = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard result.count < limit else { throw NativeUpdateFailure.malformed }
            result.append(byte)
        }
        return result
    }
    func download(from url: URL, limit: Int64) async throws -> URL {
        try await download(from: url, limit: limit, progress: { _, _ in })
    }
    func download(from url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        // Per-download delegate enforces the signed size during transfer, not just afterwards.
        let delegate = NativeUpdateHTTP(limit: min(limit,self.limit), progress: progress)
        let session = delegate.session(); defer { session.invalidateAndCancel() }
        let (temporary,response) = try await session.download(for: request(url))
        try validate(response, limit: min(limit,self.limit))
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 && Int64(size) <= min(limit,self.limit) else { try? FileManager.default.removeItem(at: temporary); throw NativeUpdateFailure.integrity }
        return temporary
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, Self.trusted(url, redirect: true) else { completionHandler(nil); return }
        var safe = request; safe.setValue(nil, forHTTPHeaderField: "Authorization"); safe.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(safe)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten >= 0, totalBytesWritten <= limit, totalBytesExpectedToWrite <= limit else { downloadTask.cancel(); return }
        progress(totalBytesWritten, limit)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard task is URLSessionDownloadTask, Bundle.main.bundleIdentifier == NativeReleaseService.testBundleID else { return }
        let log = Logger(subsystem: NativeReleaseService.testBundleID, category: "updates")
        for transaction in metrics.transactionMetrics {
            let host = transaction.request.url?.host ?? "unknown"
            let status = (transaction.response as? HTTPURLResponse)?.statusCode ?? 0
            log.notice("ZIP request host=\(host, privacy: .public) status=\(status) bytes=\(transaction.countOfResponseBodyBytesReceived)")
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

struct NativeReleaseService {
    static let maximumArchiveBytes = UpdateZIPPreflight.maximumArchiveBytes
    static let legacyArchiveBytes: Int64 = 536_870_912
    static let bundleID = "com.lsjop.helldivers2fx.native.phase1"
    static let testBundleID = bundleID + ".update-test"
    static let testChannel = "update-test"
    static let api = URL(string: "https://api.github.com/repos/\(NativeUpdateHTTP.repository)/releases?per_page=100&page=1")!
    let transport: NativeUpdateTransport
    let publicKey: Data?
    init(transport: NativeUpdateTransport = NativeUpdateHTTP(), publicKey: Data? = nil) { self.transport = transport; self.publicKey = publicKey }

    func check(version: String, build: Int, channel: String, osVersion: String, architecture: String) async throws -> NativeReleaseResult {
        guard ["stable","preview",Self.testChannel].contains(channel), build > 0 else { throw NativeUpdateFailure.malformed }
        let local = try NativeVersion(version)
        var releases: [NativeRelease] = []
        for page in 1...5 {
            let url = URL(string: "https://api.github.com/repos/\(NativeUpdateHTTP.repository)/releases?per_page=100&page=\(page)")!
            let bytes = try await transport.data(from: url, limit: 2_097_152)
            let values: [NativeRelease]
            do { values = try JSONDecoder().decode([NativeRelease].self, from: bytes) } catch { throw NativeUpdateFailure.malformed }
            releases += values
            if values.count < 100 { break }
            if page == 5 { throw NativeUpdateFailure.malformed } // Incomplete listing must never mean up to date.
        }
        let isTest = channel == Self.testChannel
        let testTag = #"^v[0-9]+\.[0-9]+\.[0-9]+-update-test\.[1-9][0-9]*$"#
        let eligible = try releases.filter { release in
            guard !release.draft else { return false }
            let test = release.tag_name.range(of: testTag, options: .regularExpression) != nil
            if isTest { return test && release.prerelease }
            return !test && (release.tag_name.hasPrefix("native-v") || release.tag_name.hasPrefix("v"))
                && (channel == "preview" || !release.prerelease)
        }.map { release -> (NativeRelease, NativeVersion) in
            let value = try NativeVersion(String(release.tag_name.dropFirst(release.tag_name.hasPrefix("native-v") ? 8 : 1)))
            guard release.prerelease || value.prerelease.isEmpty else { throw NativeUpdateFailure.malformed }
            return (release,value)
        }.sorted { $0.1 > $1.1 }
        guard let (release,remote) = eligible.first else { return .noReleases }
        guard release.html_url.scheme == "https", release.html_url.host == "github.com", release.html_url.path == "/\(NativeUpdateHTTP.repository)/releases/tag/\(release.tag_name)", release.html_url.query == nil, release.html_url.user == nil else { throw NativeUpdateFailure.malformed }
        let legacy = release.tag_name.hasPrefix("native-v")
        let modern = !legacy && release.assets.contains {
            $0.name == "update-manifest-v3.json" || $0.name == "update-manifest-v3.sig"
        }
        let manifestName = legacy ? "native-update.json" : modern ? "update-manifest-v3.json" : "update-manifest.json"
        let signatureName = legacy ? "native-update.json.sig" : modern ? "update-manifest-v3.sig" : "update-manifest.sig"
        guard release.assets.filter({ $0.name == manifestName }).count == 1, release.assets.filter({ $0.name == signatureName }).count == 1,
              let manifestAsset = release.assets.first(where: { $0.name == manifestName }), let signatureAsset = release.assets.first(where: { $0.name == signatureName }) else { throw NativeUpdateFailure.missingAsset }
        func assetURL(_ asset: NativeRelease.Asset) throws -> URL {
            guard NativeUpdateHTTP.trusted(asset.browser_download_url), asset.browser_download_url.path == "/\(NativeUpdateHTTP.repository)/releases/download/\(release.tag_name)/\(asset.name)", asset.size > 0 else { throw NativeUpdateFailure.malformed }
            return asset.browser_download_url
        }
        let manifestBytes = try await transport.data(from: assetURL(manifestAsset), limit: 65536)
        let signatureBytes = try await transport.data(from: assetURL(signatureAsset), limit: 1024)
        let signature = Data(base64Encoded: String(decoding: signatureBytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        guard let signature, signature.count == 64 else { throw NativeUpdateFailure.signature }
        if !legacy && publicKey == nil { throw NativeUpdateFailure.unconfigured }
        var verified = false
        if let publicKey {
            guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey), key.isValidSignature(signature, for: manifestBytes) else { throw NativeUpdateFailure.signature }
            verified = true
        }
        let manifest: NativeUpdateManifest
        do { manifest = try JSONDecoder().decode(NativeUpdateManifest.self, from: manifestBytes) } catch { throw NativeUpdateFailure.malformed }
        guard [1, 2, 3].contains(manifest.schema), !modern || manifest.schema == 3,
              manifest.bundleID == (isTest ? Self.testBundleID : Self.bundleID), manifest.version == String(release.tag_name.dropFirst(legacy ? 8 : 1)), manifest.build > 0,
              manifest.channel == (release.prerelease ? "preview" : "stable"), manifest.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              manifest.length > 0, manifest.length <= Self.archiveLimit(manifest.schema), manifest.archive == (legacy ? "HD2FXLauncher-\(manifest.version).zip" : "HD2FXNative-v\(manifest.version)-arm64.zip"),
              legacy || manifest.sourceCommit?.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else { throw NativeUpdateFailure.malformed }
        if manifest.schema == 3 {
            guard !legacy, verified, manifest.architecture == "arm64", let components = manifest.components else {
                throw NativeUpdateFailure.malformed
            }
            try components.validate(version: manifest.version, build: manifest.build)
        }
        guard manifest.platform == "macOS", [architecture,"universal"].contains(manifest.architecture),
              manifest.minimumSystemVersion.range(of: #"^[0-9]+\.[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              osVersion.compare(manifest.minimumSystemVersion, options: .numeric) != .orderedAscending else { throw NativeUpdateFailure.incompatible }
        guard release.assets.filter({ $0.name == manifest.archive }).count == 1, let archive = release.assets.first(where: { $0.name == manifest.archive }) else { throw NativeUpdateFailure.missingAsset }
        _ = try assetURL(archive)
        guard archive.size == manifest.length else { throw NativeUpdateFailure.integrity }
        // Both marketing version and monotonically increasing build must permit an upgrade.
        if remote < local || manifest.build < build { return .upToDate }
        if remote == local && manifest.build == build { return .upToDate }
        guard manifest.build > build else { throw NativeUpdateFailure.malformed }
        return .available(NativeUpdateCandidate(release: release, manifest: manifest, archive: archive, signatureVerified: verified, manifestBytes: manifestBytes, manifestSignature: signature))
    }

    /// Revalidate the cache at the install boundary; a prior download is not current proof.
    func verifyForInstallation(_ candidate: NativeUpdateCandidate, archive: URL) throws {
        guard candidate.signatureVerified, let publicKey else { throw NativeUpdateFailure.unconfigured }
        try Self.verifyArchive(candidate.manifest, publicKey: publicKey, archive: archive)
    }

    static func archiveLimit(_ schema: Int) -> Int64 {
        schema == 3 ? maximumArchiveBytes : legacyArchiveBytes
    }

    @discardableResult
    static func verifyArchive(_ manifest: NativeUpdateManifest, publicKey: Data, archive: URL) throws -> Int {
        guard [2, 3].contains(manifest.schema),
              manifest.length > 0, manifest.length <= archiveLimit(manifest.schema),
              try ComponentUpdate.fileDigest(archive, length: manifest.length) == manifest.sha256 else {
            throw NativeUpdateFailure.integrity
        }
        // Schema 3 signs the bounded full ZIP SHA-256 and target tree in the manifest.
        // Keep the original independent ZIP signature for legacy clients and artifacts.
        if manifest.schema == 2 {
            guard let encoded = manifest.archiveEdSignature, let signature = Data(base64Encoded: encoded),
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
                  key.isValidSignature(signature, for: try Data(contentsOf: archive, options: .mappedIfSafe)) else {
                throw NativeUpdateFailure.signature
            }
        }
        return try UpdateZIPPreflight.validate(archive)
    }

    func download(_ candidate: NativeUpdateCandidate, to directory: URL, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in },
                  verifying: @escaping @Sendable () async -> Void = {}) async throws -> URL {
        guard candidate.signatureVerified, publicKey?.count == 32 else { throw NativeUpdateFailure.unconfigured }
        guard candidate.manifest.length > 0, candidate.manifest.length <= Self.archiveLimit(candidate.manifest.schema) else {
            throw NativeUpdateFailure.integrity
        }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try fm.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory, (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(), try directory.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
              directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL else { throw NativeUpdateFailure.download }
        let free = try fm.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber
        guard let free, free.int64Value > candidate.manifest.length + 104_857_600 else { throw NativeUpdateFailure.diskSpace }
        let file = try await transport.download(from: candidate.archive.browser_download_url, limit: candidate.manifest.length, progress: progress)
        defer { try? fm.removeItem(at: file) }
        try Task.checkCancellation()
        await verifying()

        // Pin source and destination with file descriptors. Never follow a transport-supplied
        // symlink or rename an unchecked path after hashing. The installer must reverify its
        // own private copy: returning a path cannot protect it against later replacement.
        let sourceFD = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard sourceFD >= 0 else { throw NativeUpdateFailure.integrity }
        let source = FileHandle(fileDescriptor: sourceFD, closeOnDealloc: true)
        defer { try? source.close() }
        var sourceStat = stat()
        guard fstat(sourceFD, &sourceStat) == 0, (sourceStat.st_mode & S_IFMT) == S_IFREG,
              sourceStat.st_size == candidate.manifest.length else { throw NativeUpdateFailure.integrity }
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw NativeUpdateFailure.download }
        defer { close(directoryFD) }
        var directoryStat = stat()
        guard fstat(directoryFD, &directoryStat) == 0, (directoryStat.st_mode & S_IFMT) == S_IFDIR,
              directoryStat.st_uid == getuid(), (directoryStat.st_mode & 0o7777) == 0o700 else { throw NativeUpdateFailure.download }
        let name = UUID().uuidString + ".zip"
        let target = directory.appendingPathComponent(name)
        let targetFD = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard targetFD >= 0 else { throw NativeUpdateFailure.download }
        let destination = FileHandle(fileDescriptor: targetFD, closeOnDealloc: true)
        var completed = false
        defer {
            try? destination.close()
            if !completed { _ = unlinkat(directoryFD, name, 0) }
        }
        var sha = SHA256(); var length: Int64 = 0
        while let chunk = try source.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation(); length += Int64(chunk.count)
            guard length <= candidate.manifest.length else { throw NativeUpdateFailure.integrity }
            try destination.write(contentsOf: chunk)
            sha.update(data: chunk)
        }
        guard length == candidate.manifest.length, sha.finalize().map({ String(format: "%02x", $0) }).joined() == candidate.manifest.sha256 else { throw NativeUpdateFailure.integrity }
        try destination.synchronize()
        var outputStat = stat(), pathStat = stat()
        guard fstat(targetFD, &outputStat) == 0, fstatat(directoryFD, name, &pathStat, AT_SYMLINK_NOFOLLOW) == 0,
              (pathStat.st_mode & S_IFMT) == S_IFREG, outputStat.st_dev == pathStat.st_dev,
              outputStat.st_ino == pathStat.st_ino, outputStat.st_size == length else { throw NativeUpdateFailure.integrity }
        if candidate.manifest.schema == 2 {
            guard let publicKey else { throw NativeUpdateFailure.unconfigured }
            try Self.verifyArchive(candidate.manifest, publicKey: publicKey, archive: target)
        } else if candidate.manifest.schema == 3 {
            try UpdateZIPPreflight.validate(target)
        }
        completed = true
        return target
    }
}

/// Schema 3 is an extension of the signed release manifest. Fixed destinations
/// keep component metadata from turning into a general file installation API.
struct ComponentUpdate: Codable {
    struct Artifact: Codable {
        let url: URL
        let length: Int64
        let sha256: String
        let expandedBytes: Int64
    }
    struct Module: Codable {
        let id: String
        let version: String
        let path: String
        let treeSHA256: String
        let artifact: Artifact
    }
    struct Plan {
        let reused: [Module]
        let downloads: [Module]
        let bytes: Int64
    }

    static let destinations = [
        "rf-fex": "Contents/Resources/Deployment/RF-FEX",
        "proton-je": "Contents/Resources/Deployment/Proton-JE",
        "runtime4": "Contents/Resources/Deployment/SteamLinuxRuntime_4"
    ]
    static let rootName = "HD2FXNative.app"
    let protocolVersion: Int
    let minimumBaseBuild: Int
    let targetTreeSHA256: String
    let targetBytes: Int64
    let core: Artifact
    let modules: [Module]

    private static func validHash(_ value: String) -> Bool {
        value.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
    }

    func validate(version: String, build: Int) throws {
        let ids = Set(modules.map(\.id))
        let current: Set<String> = ["rf-fex", "proton-je"]
        guard protocolVersion == 1, minimumBaseBuild > 0, minimumBaseBuild < build,
              (1...NativeReleaseService.maximumArchiveBytes).contains(targetBytes),
              Self.validHash(targetTreeSHA256),
              ids.count == modules.count,
              ids.isEmpty || ids == current || ids == Set(Self.destinations.keys) else {
            throw NativeUpdateFailure.malformed
        }
        func validateArtifact(_ item: Artifact, name: String, currentTagOnly: Bool) throws {
            let parts = item.url.path.split(separator: "/")
            guard NativeUpdateHTTP.trusted(item.url), parts.count == 6,
                  parts[0] == "LSJOP", parts[1] == "helldivers2-fx-launcher",
                  parts[2] == "releases", parts[3] == "download", parts[5] == name,
                  (1...NativeReleaseService.maximumArchiveBytes).contains(item.length),
                  (1...targetBytes).contains(item.expandedBytes), Self.validHash(item.sha256) else {
                throw NativeUpdateFailure.malformed
            }
            let tag = String(parts[4])
            guard tag.hasPrefix("v"), (!currentTagOnly || tag == "v" + version) else { throw NativeUpdateFailure.malformed }
            _ = try NativeVersion(String(tag.dropFirst()))
        }
        try validateArtifact(core, name: "HD2FXNative-v\(version)-core-arm64.zip", currentTagOnly: true)
        var bytes = core.expandedBytes
        for item in modules {
            guard Self.destinations[item.id] == item.path, Self.validHash(item.treeSHA256),
                  item.version.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$"#, options: .regularExpression) != nil else {
                throw NativeUpdateFailure.malformed
            }
            try validateArtifact(item.artifact, name: "\(item.id)-\(item.treeSHA256).zip", currentTagOnly: false)
            bytes += item.artifact.expandedBytes
        }
        guard bytes == targetBytes else { throw NativeUpdateFailure.malformed }
    }

    func plan(currentBuild: Int, fullBytes: Int64, fingerprint: (Module) throws -> String?) throws -> Plan? {
        guard !modules.isEmpty, currentBuild >= minimumBaseBuild else { return nil }
        var reused: [Module] = [], downloads: [Module] = []
        var bytes = core.length
        for item in modules {
            if try fingerprint(item) == item.treeSHA256 { reused.append(item) }
            else { downloads.append(item); bytes += item.artifact.length }
        }
        guard bytes < fullBytes else { return nil }
        return Plan(reused: reused, downloads: downloads, bytes: bytes)
    }

    static func fileDigest(_ url: URL, length: Int64) throws -> String {
        guard (0...NativeReleaseService.maximumArchiveBytes).contains(length) else { throw NativeUpdateFailure.integrity }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw NativeUpdateFailure.integrity }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size == length else {
            throw NativeUpdateFailure.integrity
        }
        var sha = SHA256(), count: Int64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            count += Int64(chunk.count)
            guard count <= length else { throw NativeUpdateFailure.integrity }
            sha.update(data: chunk)
        }
        guard count == length else { throw NativeUpdateFailure.integrity }
        return hex(sha.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    /// Complete inventory of relative paths, type, permissions, lengths and content.
    /// The app's actual code signature is verified separately.
    static func tree(_ directory: URL, limit: Int64) throws -> (hash: String, bytes: Int64) {
        let fm = FileManager.default
        guard directory.path == directory.resolvingSymlinksInPath().path,
              let entries = fm.enumerator(at: directory, includingPropertiesForKeys: nil),
              try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw NativeUpdateFailure.integrity
        }
        var inventory: [UpdateArchiveEntry] = [.init(path: rootName, kind: .directory)]
        var records: [(String, String)] = []
        var bytes: Int64 = 0
        for case let item as URL in entries {
            try Task.checkCancellation()
            var metadata = stat()
            guard records.count < 19_998, lstat(item.path, &metadata) == 0,
                  metadata.st_mode & 0o7000 == 0 else { throw NativeUpdateFailure.integrity }
            let name = String(item.path.dropFirst(directory.path.count + 1))
            let kind: UpdateArchiveEntry.Kind
            let payload: String
            switch metadata.st_mode & S_IFMT {
            case S_IFDIR:
                kind = .directory
                payload = "d"
            case S_IFLNK:
                let target = try fm.destinationOfSymbolicLink(atPath: item.path)
                kind = .symbolicLink(target)
                payload = "l\0" + target
                bytes += Int64(target.utf8.count)
            case S_IFREG:
                guard metadata.st_size >= 0, metadata.st_size <= limit - bytes else { throw NativeUpdateFailure.integrity }
                kind = .file
                bytes += metadata.st_size
                payload = "f\0\(metadata.st_size)\0" + (try fileDigest(item, length: metadata.st_size))
            default:
                throw NativeUpdateFailure.integrity
            }
            guard bytes <= limit else { throw NativeUpdateFailure.integrity }
            inventory.append(.init(path: rootName + "/" + name, kind: kind))
            records.append((name, "\(name)\0\(metadata.st_mode & 0o777)\0\(payload)\0"))
        }
        try UpdateArchivePathPolicy.validate(inventory, expectedRoot: rootName)
        var sha = SHA256()
        for record in records.sorted(by: { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }) {
            sha.update(data: Data(record.1.utf8))
        }
        return (hex(sha.finalize()), bytes)
    }

    static func requireAbsent(_ item: URL) throws {
        var metadata = stat()
        guard lstat(item.path, &metadata) != 0, errno == ENOENT else { throw NativeUpdateFailure.integrity }
    }

    func verifyTarget(_ app: URL, manifest: NativeUpdateManifest, publicKey: Data) throws {
        if !modules.contains(where: { $0.id == "runtime4" }),
           let relative = Self.destinations["runtime4"] {
            try Self.requireAbsent(app.appendingPathComponent(relative))
        }
        let inventory = try Self.tree(app, limit: targetBytes)
        guard inventory.hash == targetTreeSHA256, inventory.bytes == targetBytes,
              let bundle = Bundle(url: app), bundle.bundleIdentifier == manifest.bundleID,
              bundle.infoDictionary?["CFBundleExecutable"] as? String == "HD2FXNative",
              bundle.infoDictionary?["CFBundleShortVersionString"] as? String == manifest.version,
              bundle.infoDictionary?["CFBundleVersion"] as? String == String(manifest.build),
              bundle.infoDictionary?["SUPublicEDKey"] as? String == publicKey.base64EncodedString(),
              let executable = bundle.executableURL,
              Bundle(url: app)?.executableArchitectures?.contains(NSNumber(value: CPU_TYPE_ARM64)) == true,
              executable.path == app.appendingPathComponent("Contents/MacOS/HD2FXNative").path else {
            throw NativeUpdateFailure.integrity
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures), nil) == errSecSuccess else {
            throw NativeUpdateFailure.integrity
        }
    }

    static func extract(_ archive: URL, at directory: URL, expectedBytes: Int64) throws {
        guard try Int64(UpdateZIPPreflight.validate(archive)) == expectedBytes else { throw NativeUpdateFailure.integrity }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", archive.path, directory.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 180, execute: timeout)
        defer { timeout.cancel() }
        task.waitUntilExit()
        try Task.checkCancellation()
        guard task.terminationStatus == 0 else { throw NativeUpdateFailure.integrity }
    }
}

extension NativeReleaseService {
    /// Prepare outside the live bundle; the Helper authenticates the resulting
    /// tree again after staging it next to the installed App.
    func prepareUpdate(_ candidate: NativeUpdateCandidate, installed: URL, to cache: URL,
                       progress: @escaping @Sendable (Int64, Int64) -> Void,
                       verifying: @escaping @Sendable () async -> Void) async throws -> URL {
        let manifest = candidate.manifest
        guard manifest.schema == 3, let components = manifest.components else {
            return try await download(candidate, to: cache, progress: progress, verifying: verifying)
        }
        guard candidate.signatureVerified, let publicKey,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(candidate.manifestSignature, for: candidate.manifestBytes) else { throw NativeUpdateFailure.signature }
        try components.validate(version: manifest.version, build: manifest.build)
        let fm = FileManager.default
        let build = Int(Bundle(url: installed)?.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
        let plan = try components.plan(currentBuild: build, fullBytes: manifest.length) { item in
            do { return try ComponentUpdate.tree(installed.appendingPathComponent(item.path), limit: item.artifact.expandedBytes).hash }
            catch is CancellationError { throw CancellationError() }
            catch { return nil }
        }
        if let plan {
            let workspace = cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try fm.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let attributes = try fm.attributesOfItem(atPath: cache.path)
                guard cache.path == cache.resolvingSymlinksInPath().path,
                      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { throw NativeUpdateFailure.download }
                let free = try fm.attributesOfFileSystem(forPath: cache.path)[.systemFreeSize] as? NSNumber
                guard let free, free.int64Value > components.targetBytes + plan.bytes * 2 + 104_857_600 else {
                    throw NativeUpdateFailure.diskSpace
                }
                try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                var received: Int64 = 0
                func fetch(_ artifact: ComponentUpdate.Artifact, into folder: URL) async throws {
                    let offset = received, total = plan.bytes
                    let temp = try await transport.download(from: artifact.url, limit: artifact.length) { bytes, _ in
                        progress(min(offset + max(0, bytes), total), total)
                    }
                    defer { try? fm.removeItem(at: temp) }
                    let archive = folder.appendingPathComponent("part.zip")
                    try fm.copyItem(at: temp, to: archive)
                    defer { try? fm.removeItem(at: archive) }
                    guard try ComponentUpdate.fileDigest(archive, length: artifact.length) == artifact.sha256 else {
                        throw NativeUpdateFailure.integrity
                    }
                    try ComponentUpdate.extract(archive, at: folder, expectedBytes: artifact.expandedBytes)
                    received += artifact.length
                    progress(received, total)
                }
                try await fetch(components.core, into: workspace)
                let app = workspace.appendingPathComponent(ComponentUpdate.rootName, isDirectory: true)
                for relative in ComponentUpdate.destinations.values {
                    let destination = app.appendingPathComponent(relative)
                    try ComponentUpdate.requireAbsent(destination)
                    guard destination.standardizedFileURL.path == destination.resolvingSymlinksInPath().path else {
                        throw NativeUpdateFailure.integrity
                    }
                }
                for item in plan.reused {
                    try fm.copyItem(at: installed.appendingPathComponent(item.path), to: app.appendingPathComponent(item.path))
                }
                for item in plan.downloads {
                    let stage = workspace.appendingPathComponent(item.id, isDirectory: true)
                    try fm.createDirectory(at: stage, withIntermediateDirectories: false)
                    try await fetch(item.artifact, into: stage)
                    let component = stage.appendingPathComponent(ComponentUpdate.rootName).appendingPathComponent(item.path)
                    guard try ComponentUpdate.tree(component, limit: item.artifact.expandedBytes).hash == item.treeSHA256 else {
                        throw NativeUpdateFailure.integrity
                    }
                    try fm.moveItem(at: component, to: app.appendingPathComponent(item.path))
                    try fm.removeItem(at: stage)
                }
                await verifying()
                try components.verifyTarget(app, manifest: manifest, publicKey: publicKey)
                try Task.checkCancellation()
                return app
            } catch {
                try? fm.removeItem(at: workspace)
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                Logger(subsystem: Self.bundleID, category: "updates").notice("Component update preparation failed; attempting verified full ZIP")
            }
        }
        return try await download(candidate, to: cache, progress: progress, verifying: verifying)
    }
}

#if DEBUG
/// Real HTTP and helper acceptance on a separate signed test bundle. Remote
/// release identities remain canonical; only the test transport maps them to loopback.
struct LoopbackUpdateFixture: NativeUpdateTransport {
    let port: Int
    private func request(_ url: URL) throws -> URL {
        guard NativeUpdateHTTP.trusted(url), var local = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NativeUpdateFailure.malformed
        }
        local.scheme = "http"; local.host = "127.0.0.1"; local.port = port
        guard let result = local.url else { throw NativeUpdateFailure.malformed }
        return result
    }

    private final class Delegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
        let limit: Int64
        let progress: @Sendable (Int64, Int64) -> Void
        init(limit: Int64, progress: @escaping @Sendable (Int64, Int64) -> Void) {
            self.limit = limit; self.progress = progress
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesWritten <= limit, totalBytesExpectedToWrite <= limit else { downloadTask.cancel(); return }
            progress(totalBytesWritten, limit)
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }

    func data(from url: URL, limit: Int) async throws -> Data {
        let file = try await download(from: url, limit: Int64(limit))
        defer { try? FileManager.default.removeItem(at: file) }
        return try Data(contentsOf: file)
    }
    func download(from url: URL, limit: Int64) async throws -> URL {
        try await download(from: url, limit: limit, progress: { _, _ in })
    }
    func download(from url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config, delegate: Delegate(limit: limit, progress: progress), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (file, response) = try await session.download(from: request(url))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.url?.host == "127.0.0.1", response.url?.port == port,
              let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              bytes > 0, Int64(bytes) <= limit else {
            try? FileManager.default.removeItem(at: file)
            throw NativeUpdateFailure.download
        }
        return file
    }
}
#endif
