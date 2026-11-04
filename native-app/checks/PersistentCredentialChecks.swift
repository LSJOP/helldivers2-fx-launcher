import Foundation
import CryptoKit
import Darwin

@main struct PersistentCredentialChecks {
 @MainActor static func main() async throws {
    let fixture = "fixture-encrypted-persistence-value"
    if CommandLine.arguments.count == 3, CommandLine.arguments[1].hasPrefix("--child-") {
        let store = LocalCredentialStore(root: URL(fileURLWithPath: CommandLine.arguments[2]))
        do {
            if CommandLine.arguments[1] == "--child-write" { try store.save(fixture, scope: "child-target", kind: .ssh) }
            else { guard try store.load(scope: "child-target", kind: .ssh) == fixture else { exit(2) } }
            exit(0)
        } catch { exit(3) }
    }
    var count = 0
    func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try value() else { throw NSError(domain: "PersistentCredentialCheck", code: count + 1, userInfo: [NSLocalizedDescriptionKey:name]) }
        count += 1; print("PASS " + name)
    }
    func fails(_ name: String, _ action: () throws -> Void) throws {
        do { try action() } catch { try check(true, name); return }
        try check(false, name)
    }
    let root = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("hd2-saved-credentials-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
    defer { try? FileManager.default.removeItem(at:root) }
    let folder = root.appendingPathComponent("credentials")
    let store = LocalCredentialStore(root:folder)
    let manager = SessionCredentialManager(store:store)
    await manager.prepare(for:"process-a", savedTarget:"target-a")
    manager.password = fixture; manager.sudoPassword = fixture + "-sudo"
    try check(try store.load(scope:"target-a", kind:.ssh) == nil, "unverified input is never persisted")
    await manager.authenticated(.ssh, value:fixture, target:"foreign")
    try check(try store.load(scope:"target-a", kind:.ssh) == nil, "foreign authentication cannot save")
    await manager.authenticated(.ssh, value:fixture, target:"process-a")
    await manager.authenticated(.sudo, value:fixture + "-sudo", target:"process-a")
    try check(manager.saved == Set(CredentialKind.allCases), "SSH and sudo save independently after proof")
    let reopened = SessionCredentialManager(store:LocalCredentialStore(root:folder))
    await reopened.prepare(for:"process-b", savedTarget:"target-a")
    try check(reopened.password == fixture && reopened.sudoPassword == fixture + "-sudo", "new manager restores both credentials across process identity changes")
    try check(!reopened.reusable(.ssh) && !reopened.reusable(.sudo), "restoration does not fake current authentication")
    let other = SessionCredentialManager(store:store)
    await other.prepare(for:"process-c", savedTarget:"different-fx-or-port")
    try check(other.isEmpty, "different connection target cannot receive saved credentials")
    for url in try FileManager.default.contentsOfDirectory(at:folder, includingPropertiesForKeys:nil) where !url.lastPathComponent.hasSuffix(".lock") {
        let bytes = try Data(contentsOf:url)
        try check(bytes.range(of:Data(fixture.utf8)) == nil, "no plaintext fixture in storage files")
        let attrs = try FileManager.default.attributesOfItem(atPath:url.path)
        try check((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600, "credential/key files are owner-only")
    }
    try check((try FileManager.default.attributesOfItem(atPath:folder.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700, "storage directory is owner-only")
    reopened.reject(.ssh)
    let afterReject = SessionCredentialManager(store:store)
    await afterReject.prepare(for:"process-d", savedTarget:"target-a")
    try check(afterReject.password.isEmpty && afterReject.sudoPassword == fixture + "-sudo", "rejected SSH stays rejected across reopening without removing sudo")
    afterReject.password = fixture + "-new"
    await afterReject.authenticated(.ssh, value:fixture + "-new", target:"process-d")
    try check(try store.load(scope:"target-a", kind:.ssh) == fixture + "-new", "fresh successful proof replaces rejected password")
    try store.save(fixture + "-other", scope:"target-b", kind:.ssh)
    afterReject.forgetSaved()
    try check(try store.load(scope:"target-a", kind:.ssh) == nil && store.load(scope:"target-a", kind:.sudo) == nil, "forget removes both roles for the selected environment")
    try check(try store.load(scope:"target-b", kind:.ssh) == fixture + "-other", "forget leaves unrelated environment untouched")
    let encrypted = try FileManager.default.contentsOfDirectory(at:folder, includingPropertiesForKeys:nil).first { $0.pathExtension == "sealed" }!
    var altered = try Data(contentsOf:encrypted); altered[0] ^= 1; try altered.write(to:encrypted)
    try fails("tampered ciphertext fails authenticated decryption") { _ = try store.load(scope:"target-b", kind:.ssh) }
    try FileManager.default.setAttributes([.posixPermissions:0o644], ofItemAtPath:folder.appendingPathComponent("installation.key").path)
    try fails("loose key permissions fail closed") { _ = try store.load(scope:"target-b", kind:.ssh) }
    try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath:folder.appendingPathComponent("installation.key").path)
    let linked = root.appendingPathComponent("linked")
    try FileManager.default.createSymbolicLink(at:linked, withDestinationURL:folder)
    try fails("symlink storage root rejected") { _ = try LocalCredentialStore(root:linked).load(scope:"target-b", kind:.ssh) }
    let failedDeleteRoot = root.appendingPathComponent("delete-failure")
    let failedDeleteStore = LocalCredentialStore(root:failedDeleteRoot)
    try failedDeleteStore.save(fixture, scope:"delete-target", kind:.ssh)
    let entry = try FileManager.default.contentsOfDirectory(at:failedDeleteRoot, includingPropertiesForKeys:nil).first { $0.pathExtension == "sealed" }!
    try FileManager.default.removeItem(at:entry)
    try FileManager.default.createDirectory(at:entry, withIntermediateDirectories:false, attributes:[.posixPermissions:0o700])
    try fails("deletion failure is reported") { try failedDeleteStore.remove(scope:"delete-target", kind:.ssh) }
    try check(try LocalCredentialStore(root:failedDeleteRoot).load(scope:"delete-target", kind:.ssh) == nil, "durable tombstone blocks reuse even after deletion failure")
    let childFolder = root.appendingPathComponent("child")
    for mode in ["--child-write","--child-read"] {
        let p = Process(); p.executableURL = URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL
        p.arguments = [mode, childFolder.path]; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit(); try check(p.terminationStatus == 0, "separate OS process " + mode)
    }
    let swapRoot = root.appendingPathComponent("scope-swap")
    let swapStore = LocalCredentialStore(root:swapRoot)
    try swapStore.save(fixture, scope:"scope-one", kind:.ssh)
    let firstFile = try FileManager.default.contentsOfDirectory(at:swapRoot, includingPropertiesForKeys:nil).first { $0.pathExtension == "sealed" }!
    let firstBytes = try Data(contentsOf:firstFile)
    try swapStore.save(fixture + "-two", scope:"scope-two", kind:.ssh)
    let secondFile = try FileManager.default.contentsOfDirectory(at:swapRoot, includingPropertiesForKeys:nil).first { $0.pathExtension == "sealed" && $0 != firstFile }!
    try firstBytes.write(to:secondFile)
    try fails("ciphertext cannot be swapped across target identities") { _ = try swapStore.load(scope:"scope-two", kind:.ssh) }
    let lockFD = open(swapRoot.appendingPathComponent(".lock").path, O_RDWR)
    guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw LocalCredentialStoreError.io }
    let beforeLock = ProcessInfo.processInfo.systemUptime
    do {
        try fails("busy storage lock fails with a bounded timeout") { _ = try swapStore.load(scope:"scope-one", kind:.ssh) }
    } catch { _ = flock(lockFD, LOCK_UN); close(lockFD); throw error }
    _ = flock(lockFD, LOCK_UN); close(lockFD)
    try check(ProcessInfo.processInfo.systemUptime - beforeLock < 2, "storage lock never waits indefinitely")
    let brokenManager = SessionCredentialManager(store:FailingStore())
    await brokenManager.prepare(for:"process-fail", savedTarget:"target-fail")
    brokenManager.password = fixture
    await brokenManager.authenticated(.ssh, value:fixture, target:"process-fail")
    try check(brokenManager.storageIssue && brokenManager.reusable(.ssh) && !brokenManager.saved.contains(.ssh), "storage errors remain visible without claiming save or blocking current authenticated session")
    print("\(count) encrypted credential persistence checks PASS; fixture-only, no Keychain or real passwords")
 }
}
private struct FailingStore: SavedCredentialStore {
 func load(scope:String,kind:CredentialKind)throws->String? { throw LocalCredentialStoreError.io }
 func save(_ secret:String,scope:String,kind:CredentialKind)throws { throw LocalCredentialStoreError.io }
 func remove(scope:String,kind:CredentialKind)throws { throw LocalCredentialStoreError.io }
}
