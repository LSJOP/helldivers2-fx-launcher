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
        let output=try await service.download(candidate,to:directory,progress: { progress.record($0,$1) })
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
        _ = try await service.download(install, to: directory)
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
