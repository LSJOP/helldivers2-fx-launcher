import Foundation
import CryptoKit
import Darwin

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
    init(limit: Int64 = 536_870_912, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) {
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
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

struct NativeReleaseService {
    static let bundleID = "com.lsjop.helldivers2fx.native.phase1"
    static let api = URL(string: "https://api.github.com/repos/\(NativeUpdateHTTP.repository)/releases?per_page=100&page=1")!
    let transport: NativeUpdateTransport
    let publicKey: Data?
    init(transport: NativeUpdateTransport = NativeUpdateHTTP(), publicKey: Data? = nil) { self.transport = transport; self.publicKey = publicKey }

    func check(version: String, build: Int, channel: String, osVersion: String, architecture: String) async throws -> NativeReleaseResult {
        guard ["stable","preview"].contains(channel), build > 0 else { throw NativeUpdateFailure.malformed }
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
        let eligible = try releases.filter { !$0.draft && ($0.tag_name.hasPrefix("native-v") || $0.tag_name.hasPrefix("v")) && (channel == "preview" || !$0.prerelease) }.map { release -> (NativeRelease, NativeVersion) in
            let value = try NativeVersion(String(release.tag_name.dropFirst(release.tag_name.hasPrefix("native-v") ? 8 : 1)))
            guard release.prerelease || value.prerelease.isEmpty else { throw NativeUpdateFailure.malformed }
            return (release,value)
        }.sorted { $0.1 > $1.1 }
        guard let (release,remote) = eligible.first else { return .noReleases }
        guard release.html_url.scheme == "https", release.html_url.host == "github.com", release.html_url.path == "/\(NativeUpdateHTTP.repository)/releases/tag/\(release.tag_name)", release.html_url.query == nil, release.html_url.user == nil else { throw NativeUpdateFailure.malformed }
        let legacy = release.tag_name.hasPrefix("native-v")
        let manifestName = legacy ? "native-update.json" : "update-manifest.json"
        let signatureName = legacy ? "native-update.json.sig" : "update-manifest.sig"
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
        guard [1, 2].contains(manifest.schema), manifest.bundleID == Self.bundleID, manifest.version == String(release.tag_name.dropFirst(legacy ? 8 : 1)), manifest.build > 0,
              manifest.channel == (release.prerelease ? "preview" : "stable"), manifest.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              manifest.length > 0, manifest.length <= 536_870_912, manifest.archive == (legacy ? "HD2FXLauncher-\(manifest.version).zip" : "HD2FXNative-v\(manifest.version)-arm64.zip"),
              legacy || manifest.sourceCommit?.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else { throw NativeUpdateFailure.malformed }
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
        return .available(NativeUpdateCandidate(release: release, manifest: manifest, archive: archive, signatureVerified: verified))
    }

    /// Revalidate the cache at the install boundary; a prior download is not current proof.
    func verifyForInstallation(_ candidate: NativeUpdateCandidate, archive: URL) throws {
        guard candidate.signatureVerified, candidate.manifest.schema == 2,
              let publicKey, publicKey.count == 32 else { throw NativeUpdateFailure.unconfigured }
        let fd = open(archive.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw NativeUpdateFailure.integrity }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size == candidate.manifest.length, info.st_size <= 536_870_912 else {
            throw NativeUpdateFailure.integrity
        }
        let bytes = try handle.read(upToCount: Int(info.st_size) + 1) ?? Data()
        guard bytes.count == candidate.manifest.length,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == candidate.manifest.sha256 else {
            throw NativeUpdateFailure.integrity
        }
        guard let encoded = candidate.manifest.archiveEdSignature, let signature = Data(base64Encoded: encoded),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: bytes) else { throw NativeUpdateFailure.signature }
        // Sparkle independently verifies the same archive signature on its private download.
        try UpdateZIPPreflight.validate(archive)
    }

    func download(_ candidate: NativeUpdateCandidate, to directory: URL, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) async throws -> URL {
        guard candidate.signatureVerified, publicKey?.count == 32 else { throw NativeUpdateFailure.unconfigured }
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
            guard let encoded = candidate.manifest.archiveEdSignature,
                  let signature = Data(base64Encoded: encoded), signature.count == 64,
                  let publicKey, let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
                  key.isValidSignature(signature, for: try Data(contentsOf: target, options: .mappedIfSafe)) else {
                throw NativeUpdateFailure.signature
            }
            try UpdateZIPPreflight.validate(target)
        }
        completed = true
        return target
    }
}
