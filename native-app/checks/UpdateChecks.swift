import Darwin
import Foundation
import CryptoKit

final class FixtureTransport: NativeUpdateTransport {
    var responses: [URL: Data] = [:]
    var fail = false
    var symlinkTarget: URL?
    var archive = Data("isolated-test-archive-not-an-app".utf8)
    func data(from url: URL, limit: Int) async throws -> Data {
        if fail { throw URLError(.notConnectedToInternet) }
        guard let value = responses[url] else { throw NativeUpdateFailure.missingAsset }
        guard value.count <= limit else { throw NativeUpdateFailure.malformed }
        return value
    }
    func download(from url: URL, limit: Int64) async throws -> URL {
        if fail { throw NativeUpdateFailure.download }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if let symlinkTarget { try FileManager.default.createSymbolicLink(at: file, withDestinationURL: symlinkTarget) }
        else { try archive.write(to: file) }
        return file
    }
    func download(from url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        progress(Int64(archive.count / 2), limit)
        return try await download(from: url, limit: limit)
    }
}
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: (Int64, Int64)?
    func record(_ current: Int64, _ total: Int64) { lock.lock(); defer { lock.unlock() }; recorded = (current,total) }
    func read() -> (Int64, Int64)? { lock.lock(); defer { lock.unlock() }; return recorded }
}

@main struct UpdateChecks {
    static func main() async throws {
        if CommandLine.arguments.contains("--live-public-check") {
            let result = try await NativeReleaseService().check(version: "0.1.0", build: 1, channel: "stable", osVersion: "26.1", architecture: "arm64")
            switch result {
            case .noReleases: print("LIVE PUBLIC CHECK: no Native release published (not up to date)")
            case .upToDate: print("LIVE PUBLIC CHECK: no newer compatible release listed")
            case .available(let candidate): print("LIVE PUBLIC CHECK: release metadata present; signature verified: \(candidate.signatureVerified)")
            }
            return
        }
        var passed = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw NSError(domain: name, code: 1) }
            passed += 1; print("PASS " + name)
        }
        func failure(_ code: NativeUpdateFailure, _ name: String, _ action: () async throws -> Void) async throws {
            do { try await action(); throw NSError(domain: "missing failure: " + name, code: 1) }
            catch let error as NativeUpdateFailure { try check(error == code, name) }
        }
        let digest = String(repeating: "a", count: 64)
        let assetBase = "https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/v1.1.0/"
        func artifact(_ name: String, size: Int64 = 90) -> ComponentUpdate.Artifact {
            .init(url: URL(string: assetBase + name)!, length: size, sha256: digest, expandedBytes: 100)
        }
        let modules = ComponentUpdate.destinations.sorted { $0.key < $1.key }.map { id, path in
            ComponentUpdate.Module(id: id, version: "fixed-1", path: path, treeSHA256: digest,
                                   artifact: artifact(id + "-" + digest + ".zip"))
        }
        let model = ComponentUpdate(protocolVersion: 1, minimumBaseBuild: 100, targetTreeSHA256: digest, targetBytes: 400,
                                    core: artifact("HD2FXNative-v1.1.0-core-arm64.zip", size: 30), modules: modules)
        try model.validate(version: "1.1.0", build: 101)
        let allReused = try model.plan(currentBuild: 100, fullBytes: 300) { _ in digest }
        try check(allReused?.bytes == 30 && allReused?.downloads.isEmpty == true && allReused?.reused.count == 3,
                  "only the Core is downloaded for three unchanged components")
        for id in ComponentUpdate.destinations.keys.sorted() {
            let plan = try model.plan(currentBuild: 100, fullBytes: 300) { $0.id == id ? nil : digest }
            try check(plan?.downloads.map(\.id) == [id] && plan?.bytes == 120, "changed or damaged component: " + id)
        }
        let multi = try model.plan(currentBuild: 100, fullBytes: 300) { $0.id == "rf-fex" ? digest : nil }
        try check(multi?.downloads.count == 2 && multi?.bytes == 210, "multi-component delta accounts for signed byte totals")
        try check(try model.plan(currentBuild: 100, fullBytes: 299) { _ in nil } == nil, "prefer full when modules cost more")
        try check(try model.plan(currentBuild: 99, fullBytes: 300) { _ in digest } == nil, "incompatible base uses full ZIP")
        let wrongVersion = ComponentUpdate(protocolVersion: 2, minimumBaseBuild: 100, targetTreeSHA256: digest,
                                           targetBytes: 400, core: model.core, modules: modules)
        try await failure(.malformed, "unknown component protocol refused") {
            try wrongVersion.validate(version: "1.1.0", build: 101)
        }
        try check(NativeReleaseService.archiveLimit(2) == 536_870_912
                  && NativeReleaseService.archiveLimit(3) == 2_147_483_648, "legacy and schema-3 limits are distinct")
        let treeRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let realDirectory = treeRoot.appendingPathComponent("Versions/B", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: treeRoot) }
        let library = realDirectory.appendingPathComponent("Library")
        try Data("library".utf8).write(to: library)
        try FileManager.default.createSymbolicLink(atPath: treeRoot.appendingPathComponent("Alias").path,
                                                   withDestinationPath: "Versions/Current/Library")
        try FileManager.default.createSymbolicLink(atPath: treeRoot.appendingPathComponent("Versions/Current").path,
                                                   withDestinationPath: "B")
        let before = try ComponentUpdate.tree(treeRoot, limit: 4096)
        try Data("changed".utf8).write(to: library)
        let after = try ComponentUpdate.tree(treeRoot, limit: 4096)
        try check(before.bytes == after.bytes && before.hash != after.hash, "framework symlinks preserve traversal of real signed files")
        let bridge = ComponentUpdate(protocolVersion: 1, minimumBaseBuild: 100,
                                     targetTreeSHA256: digest, targetBytes: 100,
                                     core: model.core, modules: [])
        try bridge.validate(version: "1.1.0", build: 101)
        try check(try bridge.plan(currentBuild: 100, fullBytes: 300) { _ in fatalError("empty bridge") } == nil,
                  "a bridge with no distributable runtime modules uses the full ZIP")
        let modernTransport = FixtureTransport()
        let modernKey = Curve25519.Signing.PrivateKey()
        let modernService = NativeReleaseService(transport: modernTransport, publicKey: modernKey.publicKey.rawRepresentation)
        let modernBase = "https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/v1.1.0/"
        let modernManifestURL = URL(string: modernBase + "update-manifest-v3.json")!
        let modernSignatureURL = URL(string: modernBase + "update-manifest-v3.sig")!
        let encodedBridge = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bridge))
        let modernManifest = try JSONSerialization.data(withJSONObject: [
            "schema": 3, "bundleID": NativeReleaseService.bundleID, "version": "1.1.0", "build": 101,
            "channel": "stable", "platform": "macOS", "architecture": "arm64", "minimumSystemVersion": "14.0",
            "archive": "HD2FXNative-v1.1.0-arm64.zip", "length": 300, "sha256": digest,
            "sourceCommit": String(repeating: "a", count: 40), "components": encodedBridge])
        modernTransport.responses[modernManifestURL] = modernManifest
        modernTransport.responses[modernSignatureURL] = try modernKey.signature(for: modernManifest).base64EncodedData()
        let modernAssets = ["update-manifest.json", "update-manifest.sig", "update-manifest-v3.json",
                            "update-manifest-v3.sig", "HD2FXNative-v1.1.0-arm64.zip"].map {
            ["name": $0, "browser_download_url": modernBase + $0, "size": 300] as [String: Any]
        }
        func modernRelease(_ assets: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: [["tag_name": "v1.1.0", "draft": false, "prerelease": false,
                "html_url": "https://github.com/LSJOP/helldivers2-fx-launcher/releases/tag/v1.1.0", "assets": assets]])
        }
        modernTransport.responses[NativeReleaseService.api] = try modernRelease(modernAssets)
        let modern = try await modernService.check(version: "1.0.4", build: 100, channel: "stable",
                                                   osVersion: "14.0", architecture: "arm64")
        if case .available(let candidate) = modern {
            try check(candidate.manifest.schema == 3 && candidate.signatureVerified, "dual-manifest release selects signed schema 3")
        } else { try check(false, "dual-manifest candidate") }
        modernTransport.responses[NativeReleaseService.api] = try modernRelease(modernAssets.filter { $0["name"] as? String != "update-manifest-v3.sig" })
        try await failure(.missingAsset, "incomplete modern signature pair fails closed") {
            _ = try await modernService.check(version: "1.0.4", build: 100, channel: "stable", osVersion: "14.0", architecture: "arm64")
        }
        let transport = FixtureTransport()
        let key = Curve25519.Signing.PrivateKey() // Ephemeral test key, never written or used for publication.
        let service = NativeReleaseService(transport: transport, publicKey: key.publicKey.rawRepresentation)
        let tag = "native-v0.2.0"
        let prefix = "https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/\(tag)/"
        let manifestURL = URL(string: prefix + "native-update.json")!
        let signatureURL = URL(string: prefix + "native-update.json.sig")!
        let archiveURL = URL(string: prefix + "HD2FXLauncher-0.2.0.zip")!
        let sha = SHA256.hash(data: transport.archive).map { String(format: "%02x",$0) }.joined()
        var manifest: [String: Any] = ["schema":1,"bundleID":NativeReleaseService.bundleID,"version":"0.2.0","build":2,"channel":"stable","platform":"macOS","architecture":"arm64","minimumSystemVersion":"14.0","archive":"HD2FXLauncher-0.2.0.zip","length":transport.archive.count,"sha256":sha]
        var assets: [[String: Any]] = [("native-update.json",manifestURL,100),("native-update.json.sig",signatureURL,88),("HD2FXLauncher-0.2.0.zip",archiveURL,transport.archive.count)].map { ["name":$0.0,"browser_download_url":$0.1.absoluteString,"size":$0.2] }
        func fixture() throws {
            let bytes = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            transport.responses[manifestURL] = bytes
            transport.responses[signatureURL] = try key.signature(for: bytes).base64EncodedData()
            transport.responses[NativeReleaseService.api] = try JSONSerialization.data(withJSONObject: [["tag_name":tag,"draft":false,"prerelease":false,"html_url":"https://github.com/LSJOP/helldivers2-fx-launcher/releases/tag/\(tag)","body":"Fixture release notes","assets":assets]])
        }
        func run(version: String = "0.1.0", build: Int = 1, os: String = "26.1", architecture: String = "arm64") async throws -> NativeReleaseResult {
            try await service.check(version: version,build: build,channel:"stable",osVersion: os,architecture:architecture)
        }
        try fixture()
        guard case .available(let candidate) = try await run() else { fatalError("candidate missing") }
        try check(candidate.signatureVerified && candidate.manifest.build == 2,"new release has valid real Ed25519 manifest signature")
        if case .upToDate = try await run(version:"0.2.0",build:2) { try check(true,"current release is up to date") } else { try check(false,"current") }
        if case .upToDate = try await run(version:"1.0.0",build:9) { try check(true,"downgrade prevented by marketing version and build") } else { try check(false,"downgrade") }
        try await failure(.incompatible,"incompatible OS") { _ = try await run(os:"13.0") }
        try await failure(.incompatible,"incompatible architecture") { _ = try await run(architecture:"x86_64") }
        transport.responses[NativeReleaseService.api] = Data("[]".utf8)
        if case .noReleases = try await run() { try check(true,"empty release list is not up to date") } else { try check(false,"empty") }
        transport.responses[NativeReleaseService.api] = Data("invalid".utf8)
        try await failure(.malformed,"malformed release metadata") { _ = try await run() }
        try fixture();transport.fail=true
        do { _ = try await run(); try check(false,"network") } catch is URLError { try check(true,"network failure never becomes up to date") }
        transport.fail=false
        let savedAssets=assets;assets.removeLast();try fixture()
        try await failure(.missingAsset,"missing archive") { _ = try await run() }
        assets=savedAssets;try fixture()
        transport.responses[signatureURL] = Data(repeating: 0,count:64).base64EncodedData()
        try await failure(.signature,"signature failure") { _ = try await run() }
        try fixture();transport.responses[manifestURL]!.append(32)
        try await failure(.signature,"manifest tampering") { _ = try await run() }
        try fixture()
        let noKey=NativeReleaseService(transport:transport)
        guard case .available(let unsigned) = try await noKey.check(version:"0.1.0",build:1,channel:"stable",osVersion:"26.1",architecture:"arm64") else { fatalError() }
        try check(!unsigned.signatureVerified,"missing trusted key never establishes signature validation")
        let directory=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await failure(.unconfigured,"download requires trusted signature") { _ = try await noKey.download(unsigned,to:directory) }
        let progress=ProgressRecorder()
        let verification = ProgressRecorder()
        let output=try await service.download(candidate,to:directory,progress: { progress.record($0,$1) }, verifying: {
            verification.record(1, 1)
        })
        try check(verification.read()?.0 == 1, "verification phase begins after download")
        try check(progress.read()?.0 == Int64(transport.archive.count / 2) && progress.read()?.1 == candidate.manifest.length,"download progress carries signed length")
        try check(try Data(contentsOf:output)==transport.archive,"verified download cached without installing")
        let symlinkTarget=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try transport.archive.write(to:symlinkTarget)
        defer { try? FileManager.default.removeItem(at:symlinkTarget) }
        transport.symlinkTarget=symlinkTarget
        try await failure(.integrity,"download refuses symlink source") { _ = try await service.download(candidate,to:directory) }
        try check(FileManager.default.fileExists(atPath:symlinkTarget.path),"rejecting symlink preserves target")
        transport.symlinkTarget=nil
        let attrs=try FileManager.default.attributesOfItem(atPath:output.path)
        try check((attrs[.posixPermissions] as? NSNumber)?.intValue==0o600,"cached archive is private")
        transport.archive[0] ^= 1
        try await failure(.integrity,"archive checksum failure") { _ = try await service.download(candidate,to:directory) }
        transport.fail=true
        try await failure(.download,"interrupted download") { _ = try await service.download(candidate,to:directory) }
        transport.fail=false
        let cancelled=Task {
            try Task.checkCancellation()
            _ = try await service.download(candidate,to:directory)
        }
        cancelled.cancel()
        do { try await cancelled.value; try check(false,"cancel") } catch is CancellationError { try check(true,"user cancellation propagates") }
        manifest["build"]=0;try fixture()
        try await failure(.malformed,"invalid build rejected") { _ = try await run() }
        manifest["build"]=2
        try check(try NativeVersion("1.0.0-preview.2") < NativeVersion("1.0.0-preview.10") && NativeVersion("1.0.0-preview.10") < NativeVersion("1.0.0"),"numeric semantic prerelease order")
        try check(!NativeUpdateHTTP.trusted(URL(string:"https://evil.example/updates.zip")!) && !NativeUpdateHTTP.trusted(URL(string:"http://github.com/LSJOP/helldivers2-fx-launcher/releases/download/native-v0.2.0/a.zip")!),"untrusted URLs and HTTP rejected")
        try check(!NativeUpdateHTTP.trusted(URL(string:"https://user:pass@github.com/LSJOP/helldivers2-fx-launcher/releases/download/native-v0.2.0/a.zip")!),"URL credentials rejected")
        try check(NativeUpdateHTTP.trusted(URL(string:"https://release-assets.githubusercontent.com/assets/example?token=temporary")!,redirect:true) && !NativeUpdateHTTP.trusted(URL(string:"https://release-assets.githubusercontent.com.evil.example/assets/example")!,redirect:true) && !NativeUpdateHTTP.trusted(URL(string:"https://release-assets.githubusercontent.com:8443/assets/example")!,redirect:true),"redirect host and port allowlist")
        // A GitHub prerelease can use a plain v1.0.0 tag; channel is a release property,
        // not necessarily a semantic-version suffix.
        let vTag = "v1.0.0"
        let vPrefix = "https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/\(vTag)/"
        let vManifestURL = URL(string:vPrefix + "update-manifest.json")!
        let vSignatureURL = URL(string:vPrefix + "update-manifest.sig")!
        let vArchiveURL = URL(string:vPrefix + "HD2FXNative-v1.0.0-arm64.zip")!
        var vManifest: [String:Any] = ["schema":1,"bundleID":NativeReleaseService.bundleID,"version":"1.0.0","build":3,"channel":"preview","platform":"macOS","architecture":"arm64","minimumSystemVersion":"14.0","archive":"HD2FXNative-v1.0.0-arm64.zip","length":transport.archive.count,"sha256":sha,"sourceCommit":String(repeating:"a",count:40)]
        var vAssets: [[String:Any]] = [("update-manifest.json",vManifestURL,100),("update-manifest.sig",vSignatureURL,88),("HD2FXNative-v1.0.0-arm64.zip",vArchiveURL,transport.archive.count)].map { ["name":$0.0,"browser_download_url":$0.1.absoluteString,"size":$0.2] }
        func vFixture() throws {
            let bytes=try JSONSerialization.data(withJSONObject:vManifest,options:[.sortedKeys])
            transport.responses[vManifestURL]=bytes
            transport.responses[vSignatureURL]=try key.signature(for:bytes).base64EncodedData()
            transport.responses[NativeReleaseService.api]=try JSONSerialization.data(withJSONObject:[["tag_name":vTag,"draft":false,"prerelease":true,"html_url":"https://github.com/LSJOP/helldivers2-fx-launcher/releases/tag/\(vTag)","body":"preview","assets":vAssets]])
        }
        try vFixture()
        try await failure(.unconfigured,"v1 release requires trusted key") { _ = try await noKey.check(version:"0.1.0",build:1,channel:"preview",osVersion:"26.1",architecture:"arm64") }
        if case .noReleases = try await run() { try check(true,"stable channel excludes plain-tag prerelease") } else { try check(false,"stable excludes preview") }
        if case .available(let release) = try await service.check(version:"0.1.0",build:1,channel:"preview",osVersion:"26.1",architecture:"arm64") {
            try check(release.signatureVerified && release.manifest.sourceCommit == String(repeating:"a",count:40),"preview accepts signed v1.0.0 with source commit")
        } else { try check(false,"preview candidate") }
        vManifest["sourceCommit"]="invalid";try vFixture()
        try await failure(.malformed,"invalid source commit rejected") { _ = try await service.check(version:"0.1.0",build:1,channel:"preview",osVersion:"26.1",architecture:"arm64") }
        vManifest["sourceCommit"]=String(repeating:"a",count:40);vManifest["bundleID"]="invalid.bundle";try vFixture()
        try await failure(.malformed,"manifest bundle identity mismatch rejected") { _ = try await service.check(version:"0.1.0",build:1,channel:"preview",osVersion:"26.1",architecture:"arm64") }
        vManifest["bundleID"]=NativeReleaseService.bundleID;vManifest["archive"]="../evil.zip";try vFixture()
        try await failure(.malformed,"manifest archive traversal rejected") { _ = try await service.check(version:"0.1.0",build:1,channel:"preview",osVersion:"26.1",architecture:"arm64") }
        vManifest["archive"]="HD2FXNative-v1.0.0-arm64.zip";vAssets.append(vAssets[2]);try vFixture()
        try await failure(.missingAsset,"ambiguous duplicate archive rejected") { _ = try await service.check(version:"0.1.0",build:1,channel:"preview",osVersion:"26.1",architecture:"arm64") }

        let testTag = "v1.0.2-update-test.1"
        let testVersion = String(testTag.dropFirst())
        let testPrefix = "https://github.com/LSJOP/helldivers2-fx-launcher/releases/download/\(testTag)/"
        let testArchive = "HD2FXNative-\(testTag)-arm64.zip"
        let testAssets = [("update-manifest.json", 100), ("update-manifest.sig", 88), (testArchive, transport.archive.count)]
            .map { ["name": $0.0, "browser_download_url": testPrefix + $0.0, "size": $0.1] as [String: Any] }
        vManifest["version"] = testVersion
        vManifest["bundleID"] = NativeReleaseService.testBundleID
        vManifest["archive"] = testArchive
        let testManifest = try JSONSerialization.data(withJSONObject: vManifest)
        transport.responses[URL(string: testPrefix + "update-manifest.json")!] = testManifest
        transport.responses[URL(string: testPrefix + "update-manifest.sig")!] = try key.signature(for: testManifest).base64EncodedData()
        transport.responses[NativeReleaseService.api] = try JSONSerialization.data(withJSONObject: [
            ["tag_name": testTag, "draft": false, "prerelease": true,
             "html_url": "https://github.com/LSJOP/helldivers2-fx-launcher/releases/tag/\(testTag)", "assets": testAssets]
        ])
        for channel in ["stable", "preview"] {
            let result = try await service.check(version: "1.0.1", build: 1, channel: channel, osVersion: "26.1", architecture: "arm64")
            if case .noReleases = result { try check(true, "test tag excluded from \(channel)") }
            else { try check(false, "test tag must stay isolated") }
        }
        let testResult = try await service.check(version: "1.0.1-update-test.1", build: 1,
                                                 channel: NativeReleaseService.testChannel, osVersion: "26.1", architecture: "arm64")
        if case .available(let candidate) = testResult {
            try check(candidate.signatureVerified && candidate.manifest.bundleID == NativeReleaseService.testBundleID,
                      "test channel requires its signed app identity")
        } else { try check(false, "test update unavailable") }

        // Schema 2 binds the archive signature to the same bytes that pass SHA-256 and path validation.
        func installCandidate(_ archiveBytes: Data, signature: String? = nil) async throws -> NativeUpdateCandidate {
            transport.archive = archiveBytes
            let document: [String: Any] = [
                "schema": 2, "bundleID": NativeReleaseService.bundleID, "version": "0.2.0", "build": 2,
                "channel": "stable", "platform": "macOS", "architecture": "arm64", "minimumSystemVersion": "14.0",
                "archive": "HD2FXLauncher-0.2.0.zip", "length": archiveBytes.count,
                "sha256": SHA256.hash(data: archiveBytes).map { String(format: "%02x", $0) }.joined(),
                "archiveEdSignature": try signature ?? key.signature(for: archiveBytes).base64EncodedString()
            ]
            let bytes = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
            transport.responses[manifestURL] = bytes
            transport.responses[signatureURL] = try key.signature(for: bytes).base64EncodedData()
            let cleanAssets: [[String: Any]] = [
                ["name": "native-update.json", "browser_download_url": manifestURL.absoluteString, "size": bytes.count],
                ["name": "native-update.json.sig", "browser_download_url": signatureURL.absoluteString, "size": 88],
                ["name": "HD2FXLauncher-0.2.0.zip", "browser_download_url": archiveURL.absoluteString, "size": archiveBytes.count]
            ]
            transport.responses[NativeReleaseService.api] = try JSONSerialization.data(withJSONObject: [[
                "tag_name": tag, "draft": false, "prerelease": false,
                "html_url": "https://github.com/LSJOP/helldivers2-fx-launcher/releases/tag/" + tag, "assets": cleanAssets
            ]])
            guard case .available(let result) = try await run() else { throw NativeUpdateFailure.malformed }
            return result
        }
        let safeZIP = Data(base64Encoded: "UEsDBBQAAAAIANYWbl3uQOUFCQAAAAcAAAAjAAAASEQyRlhOYXRpdmUuYXBwL0NvbnRlbnRzL0luZm8ucGxpc3RLy6woKS1KBQBQSwECFAMUAAAACADWFm5d7kDlBQkAAAAHAAAAIwAAAAAAAAAAAAAAgAEAAAAASEQyRlhOYXRpdmUuYXBwL0NvbnRlbnRzL0luZm8ucGxpc3RQSwUGAAAAAAEAAQBRAAAASgAAAAAA")!
        let install = try await installCandidate(safeZIP)
        let installCache = try await service.download(install, to: directory)
        try service.verifyForInstallation(install, archive: installCache)
        try check(true, "install boundary revalidates signed archive")
        try Data(repeating: 0, count: safeZIP.count).write(to: installCache)
        try await failure(.integrity, "cache mutation after download is rejected at installation") {
            try service.verifyForInstallation(install, archive: installCache)
        }
        try FileManager.default.removeItem(at: installCache)
        try FileManager.default.createSymbolicLink(at: installCache, withDestinationURL: directory)
        try await failure(.integrity, "install cache symlink is rejected") {
            try service.verifyForInstallation(install, archive: installCache)
        }
        let fifo = directory.appendingPathComponent("install-cache-fifo")
        guard mkfifo(fifo.path, 0o600) == 0 else { throw POSIXError(.EIO) }
        try await failure(.integrity, "install cache FIFO is rejected without waiting for a writer") {
            try service.verifyForInstallation(install, archive: fifo)
        }

        try FileManager.default.removeItem(at: installCache)
        try check(true, "signed schema 2 archive passes digest, archive signature and path preflight")
        let unsafeZIP = Data(base64Encoded: "UEsDBBQAAAAIANYWbl3uQOUFCQAAAAcAAAAcAAAASEQyRlhOYXRpdmUuYXBwLy4uLy4uL2VzY2FwZUvLrCgpLUoFAFBLAQIUAxQAAAAIANYWbl3uQOUFCQAAAAcAAAAcAAAAAAAAAAAAAACAAQAAAABIRDJGWE5hdGl2ZS5hcHAvLi4vLi4vZXNjYXBlUEsFBgAAAAABAAEASgAAAEMAAAAAAA==")!
        let unsafeInstall = try await installCandidate(unsafeZIP)
        do {
            _ = try await service.download(unsafeInstall, to: directory)
            throw NSError(domain: "signed malicious ZIP passed", code: 1)
        } catch is UpdateArchivePathError {
            try check(true, "valid publisher signature never bypasses archive path policy")
        }
        let wrongSignature = try key.signature(for: Data("different archive".utf8)).base64EncodedString()
        let tamperedInstall = try await installCandidate(safeZIP, signature: wrongSignature)
        try await failure(.signature, "archive signature bound independently from signed manifest") {
            _ = try await service.download(tamperedInstall, to: directory)
        }
        print("\(passed) update service checks PASS")
    }
}
