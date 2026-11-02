import Foundation
import CryptoKit

final class FixtureTransport: NativeUpdateTransport {
    var responses: [URL: Data] = [:]
    var fail = false
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
        try archive.write(to: file)
        return file
    }
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
        let output=try await service.download(candidate,to:directory)
        try check(try Data(contentsOf:output)==transport.archive,"verified download cached without installing")
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
        print("\(passed) update service checks PASS")
    }
}
