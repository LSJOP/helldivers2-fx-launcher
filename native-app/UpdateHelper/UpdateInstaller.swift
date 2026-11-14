import AppKit
import CryptoKit
import Darwin
import Security

private let recoveryBusyExit: Int32 = 75

@main
enum UpdateInstaller {
    static func main() {
        do {
            if CommandLine.arguments.dropFirst().first == "--recover" { try recover() }
            else { try install() }
        }
        catch {
            fputs("Update failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private enum Phase: String, Codable { case preparing, exchangePending, awaitingStartup, confirmed, rollingBack }
    private struct BundleIdentity: Codable, Equatable {
        let device: dev_t
        let inode: ino_t
        init(_ pair: (dev_t, ino_t)) { (device, inode) = pair }
    }
    private struct Transaction: Codable {
        var phase: Phase
        let target: String
        let old: BundleIdentity
        let oldVersion: String
        let oldBuild: String
        let key: String
        var new: BundleIdentity?
        var newVersion: String?
        var newBuild: String?
    }

    private static var installedBundle: URL {
        URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func persist(_ state: Transaction, in directory: URL, fd: Int32) throws {
        let url = directory.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.synchronize()
        guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
    }

    private static func recover() throws {
        let args = CommandLine.arguments
        guard args.count == 4, let pid = Int32(args[2]), pid == getppid(),
              let token = UUID(uuidString: args[3]), let running = NSRunningApplication(processIdentifier: pid)
        else { throw NativeUpdateFailure.integrity }
        let installed = installedBundle
        guard installed.resolvingSymlinksInPath().path == installed.path,
              running.bundleURL?.resolvingSymlinksInPath() == installed else { throw NativeUpdateFailure.integrity }
        let parent = installed.deletingLastPathComponent()
        let directory = parent.appendingPathComponent(".HD2FXNative-update", isDirectory: true)
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw NativeUpdateFailure.integrity }
        defer { close(parentFD) }
        let fd = openat(parentFD, directory.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return }
        guard fd >= 0 else { throw NativeUpdateFailure.integrity }
        defer { close(fd) }
        var workspace = stat()
        guard fstat(fd, &workspace) == 0, workspace.st_uid == getuid(),
              workspace.st_mode & 0o777 == 0o700 else { throw NativeUpdateFailure.integrity }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if errno == EWOULDBLOCK { exit(recoveryBusyExit) }
            throw POSIXError(.EIO)
        }

        var state = try JSONDecoder().decode(Transaction.self, from: readRegularFile(directory.appendingPathComponent("state.json"), limit: 16_384))
        guard state.target == installed.path,
              let bundle = Bundle(url: installed), let identifier = bundle.bundleIdentifier,
              [NativeReleaseService.bundleID, NativeReleaseService.testBundleID].contains(identifier),
              bundle.infoDictionary?["SUPublicEDKey"] as? String == state.key
        else { throw NativeUpdateFailure.integrity }
        let name = installed.lastPathComponent
        let staged = directory.appendingPathComponent("HD2FXNative.app")
        let installedIdentity = try identity(parentFD, name)
        if BundleIdentity(installedIdentity) == state.old {
            _ = try validate(installed, version: state.oldVersion, build: state.oldBuild, key: state.key, identifier: identifier)
            guard state.phase != .confirmed else { throw NativeUpdateFailure.integrity }
            try archiveTransaction(directory, parent: parent, message: "interrupted transaction recovered with original bundle")
            return
        }

        guard let new = state.new, BundleIdentity(installedIdentity) == new,
              let version = state.newVersion, let build = state.newBuild, state.phase != .preparing,
              BundleIdentity(try identity(fd, staged.lastPathComponent)) == state.old else { throw NativeUpdateFailure.integrity }
        _ = try validate(installed, version: version, build: build, key: state.key, identifier: identifier)
        let oldExecutable = try validate(staged, version: state.oldVersion, build: state.oldBuild, key: state.key, identifier: identifier)
        if state.phase == .confirmed {
            try archiveTransaction(directory, parent: parent, message: "confirmed transaction cleaned up")
            return
        }
        let oldIdentity = try identity(fd, staged.lastPathComponent)
        let ready = directory.appendingPathComponent("recover-\(token.uuidString)")
        try Data().write(to: ready, options: .withoutOverwriting)
        guard wait(seconds: 30, until: { kill(pid, 0) == -1 && errno == ESRCH }),
              !runningAt(installed, identifier: identifier) else { throw POSIXError(.ETIMEDOUT) }
        state.phase = .rollingBack
        // A full volume must not prevent restoring the verified original bundle.
        try? persist(state, in: directory, fd: fd)
        try exchange(parentFD, name, fd, staged.lastPathComponent, installedIdentity, oldIdentity)
        try launchAndConfirm(installed.appendingPathComponent(oldExecutable), directory: directory)
        try archiveTransaction(directory, parent: parent, message: "interrupted exchange rolled back and original confirmed")
    }

    private static func runningAt(_ installed: URL, identifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains {
            !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath() == installed
        }
    }

    private static func archiveTransaction(_ directory: URL, parent: URL, message: String) throws {
        let log = try FileHandle(forWritingTo: directory.appendingPathComponent("journal.log"))
        defer { try? log.close() }
        try log.seekToEnd()
        try log.write(contentsOf: Data("\(Date()): \(message)\n".utf8))
        try log.synchronize()
        let history = parent.appendingPathComponent(".HD2FXNative-update-" + UUID().uuidString)
        try FileManager.default.moveItem(at: directory, to: history)
        for name in ["archive.zip", "HD2FXNative.app"] {
            try? FileManager.default.removeItem(at: history.appendingPathComponent(name))
        }
    }

    static func install() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, let pid = Int32(arguments[2]), pid == getppid(),
              let running = NSRunningApplication(processIdentifier: pid),
              CommandLine.arguments[0].hasPrefix("/") else { throw NativeUpdateFailure.integrity }
        let installed = URL(fileURLWithPath: arguments[0])
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let current = Bundle(url: installed), running.bundleURL?.resolvingSymlinksInPath() == installed.resolvingSymlinksInPath(),
              let identifier = current.bundleIdentifier,
              [NativeReleaseService.bundleID, NativeReleaseService.testBundleID].contains(identifier),
              let currentBuild = current.infoDictionary?["CFBundleVersion"] as? String, let build = Int(currentBuild),
              let currentVersion = current.infoDictionary?["CFBundleShortVersionString"] as? String,
              let encoded = current.infoDictionary?["SUPublicEDKey"] as? String,
              let publicBytes = Data(base64Encoded: encoded) else { throw NativeUpdateFailure.integrity }
        let parent = installed.deletingLastPathComponent()
        guard installed.path == installed.resolvingSymlinksInPath().standardizedFileURL.path,
              FileManager.default.isWritableFile(atPath: parent.path) else { throw POSIXError(.EACCES) }
        let transaction = parent.appendingPathComponent(".HD2FXNative-update", isDirectory: true)
        guard mkdir(transaction.path, 0o700) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw NativeUpdateFailure.integrity }
        defer { close(parentFD) }
        let transactionFD = openat(parentFD, transaction.lastPathComponent,
                                   O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard transactionFD >= 0 else { throw NativeUpdateFailure.integrity }
        defer { close(transactionFD) }
        var workspace = stat()
        guard fstat(transactionFD, &workspace) == 0, workspace.st_uid == getuid(),
              workspace.st_mode & 0o777 == 0o700, flock(transactionFD, LOCK_EX | LOCK_NB) == 0 else { throw NativeUpdateFailure.integrity }
        let log = transaction.appendingPathComponent("journal.log")
        let staged = transaction.appendingPathComponent("HD2FXNative.app", isDirectory: true)
        var swapped = false
        var preserve = false
        var finished = false
        defer {
            if !preserve && !swapped && FileManager.default.fileExists(atPath: transaction.path) {
                try? FileManager.default.removeItem(at: transaction.appendingPathComponent("archive.zip"))
                try? FileManager.default.removeItem(at: staged)
                let history = parent.appendingPathComponent(".HD2FXNative-update-" + UUID().uuidString)
                try? FileManager.default.moveItem(at: transaction, to: history)
            }
        }
        func record(_ phase: String) throws {
            // A successful journal write precedes every mutation of the installed bundle.
            let entry = "\(Date()): \(phase) [\(installed.lastPathComponent)]\n"
            if !FileManager.default.fileExists(atPath: log.path) {
                try Data(entry.utf8).write(to: log, options: .withoutOverwriting)
            } else {
                let output = try FileHandle(forWritingTo: log)
                defer { try? output.close() }
                try output.seekToEnd()
                try output.write(contentsOf: Data(entry.utf8))
                try output.synchronize()
            }
        }
        try record("transaction started")
        _ = try validate(installed, version: currentVersion, build: currentBuild, key: encoded, identifier: identifier)
        let old = try identity(parentFD, installed.lastPathComponent)
        var state = Transaction(phase: .preparing, target: installed.path, old: BundleIdentity(old),
                                oldVersion: currentVersion, oldBuild: currentBuild, key: encoded)
        try persist(state, in: transaction, fd: transactionFD)
        defer { if !finished { try? record("transaction ended with error") } }
        let request = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let manifestBytes = try readRegularFile(request.appendingPathComponent("manifest.json"), limit: 65_536)
        let signature = try readRegularFile(request.appendingPathComponent("manifest.sig"), limit: 64)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
        guard manifestBytes.count <= 65_536, key.isValidSignature(signature, for: manifestBytes) else {
            throw NativeUpdateFailure.signature
        }
        let manifest = try JSONDecoder().decode(NativeUpdateManifest.self, from: manifestBytes)
        guard manifest.bundleID == identifier, manifest.build > build,
              try NativeVersion(manifest.version) >= NativeVersion(currentVersion) else { throw NativeUpdateFailure.incompatible }
        let archive = transaction.appendingPathComponent("archive.zip")
        func requireSpace(_ bytes: Int64) throws {
            var volume = statfs()
            guard statfs(transaction.path, &volume) == 0 else { throw POSIXError(.EIO) }
            let available = UInt64(volume.f_bavail) * UInt64(volume.f_bsize)
            guard available > UInt64(bytes) + 1_048_576 else { throw NativeUpdateFailure.diskSpace }
        }
        try requireSpace(manifest.length)
        try copyArchive(request.appendingPathComponent("archive.zip"), to: archive, length: manifest.length)
        let expanded = try NativeReleaseService.verifyArchive(manifest, publicKey: publicBytes, archive: archive)
        try requireSpace(Int64(expanded))
        try record("verified")
        let extractor = try spawn("/usr/bin/ditto", ["-x", "-k", archive.path, transaction.path])
        extractor.waitUntilExit()
        guard extractor.terminationStatus == 0 else { throw NativeUpdateFailure.integrity }
        let newExecutable = try validate(staged, version: manifest.version, build: String(manifest.build), key: encoded, identifier: identifier)
        let oldExecutable = try validate(installed, version: currentVersion, build: currentBuild, key: encoded, identifier: identifier)
        let installedIdentity = try identity(parentFD, installed.lastPathComponent)
        let stagedIdentity = try identity(transactionFD, staged.lastPathComponent)
        guard installedIdentity == old else { throw NativeUpdateFailure.integrity }
        state.new = BundleIdentity(stagedIdentity)
        state.newVersion = manifest.version
        state.newBuild = String(manifest.build)
        state.phase = .exchangePending
        try persist(state, in: transaction, fd: transactionFD)
        try record("prepared")
        try Data().write(to: request.appendingPathComponent("prepared"), options: .withoutOverwriting)
        guard wait(seconds: 30, until: { kill(pid, 0) == -1 && errno == ESRCH }) else {
            throw POSIXError(.ETIMEDOUT)
        }
        do {
            guard !runningAt(installed, identifier: identifier) else { throw NativeUpdateFailure.integrity }
            try record("exchange pending")
            try exchange(parentFD, installed.lastPathComponent, transactionFD, staged.lastPathComponent, installedIdentity, stagedIdentity)
            swapped = true
            state.phase = .awaitingStartup
            try persist(state, in: transaction, fd: transactionFD)
            try record("awaiting startup confirmation")
            try launchAndConfirm(installed.appendingPathComponent(newExecutable), directory: transaction)

        } catch {
            let failure = error
            do {
                if swapped {
                    state.phase = .rollingBack
                    // The prior durable record already binds both bundle identities.
                    // Proceed with the identity-checked exchange even if the journal cannot grow.
                    try? persist(state, in: transaction, fd: transactionFD)
                    try exchange(parentFD, installed.lastPathComponent, transactionFD, staged.lastPathComponent, stagedIdentity, installedIdentity)
                    swapped = false
                }
                guard try identity(parentFD, installed.lastPathComponent) == installedIdentity else {
                    throw NativeUpdateFailure.integrity
                }
                _ = try validate(installed, version: currentVersion, build: currentBuild, key: encoded, identifier: identifier)
                try launchAndConfirm(installed.appendingPathComponent(oldExecutable), directory: transaction)
                try record("old version restored and confirmed")
            } catch {
                preserve = true
                try? record("automatic recovery failed: \(error)")
                throw error
            }
            throw failure
        }
        // Once the new app is confirmed, a journal failure must not replace
        // the bundle underneath that now-running process.
        state.phase = .confirmed
        try persist(state, in: transaction, fd: transactionFD)
        try record("confirmed")
        swapped = false
        finished = true
        // Preserve the journal and receipts without preventing the next transaction.
        let history = parent.appendingPathComponent(".HD2FXNative-update-" + UUID().uuidString)
        try FileManager.default.moveItem(at: transaction, to: history)
        try? FileManager.default.removeItem(at: history.appendingPathComponent("archive.zip"))
        try? FileManager.default.removeItem(at: history.appendingPathComponent("HD2FXNative.app"))
    }

    private static func copyArchive(_ source: URL, to archive: URL, length: Int64) throws {
        guard length > 0, length <= 536_870_912 else { throw NativeUpdateFailure.integrity }
        let inputFD = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard inputFD >= 0 else { throw NativeUpdateFailure.integrity }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
        defer { try? input.close() }
        var info = stat()
        guard fstat(inputFD, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size == length else {
            throw NativeUpdateFailure.integrity
        }
        let outputFD = open(archive.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard outputFD >= 0 else { throw NativeUpdateFailure.integrity }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        defer { try? output.close() }
        var remaining = length
        while remaining > 0 {
            let chunk = try input.read(upToCount: Int(min(remaining, 1_048_576))) ?? Data()
            guard !chunk.isEmpty else { throw NativeUpdateFailure.integrity }
            try output.write(contentsOf: chunk)
            remaining -= Int64(chunk.count)
        }
        try output.synchronize()
    }

    private static func validate(_ app: URL, version: String, build: String, key: String, identifier: String) throws -> String {
        var code: SecStaticCode?
        guard app.resolvingSymlinksInPath().path == app.standardizedFileURL.path,
              SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), nil) == errSecSuccess,
              let bundle = Bundle(url: app),
              bundle.bundleIdentifier == identifier,
              bundle.infoDictionary?["CFBundleVersion"] as? String == build,
              bundle.infoDictionary?["CFBundleShortVersionString"] as? String == version,
              bundle.infoDictionary?["SUPublicEDKey"] as? String == key,
              bundle.infoDictionary?["CFBundleExecutable"] as? String == "HD2FXNative" else {
            throw NativeUpdateFailure.integrity
        }
        return "Contents/MacOS/HD2FXNative"
    }

    private static func identity(_ directory: Int32, _ name: String) throws -> (dev_t, ino_t) {
        var info = stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_mode & S_IFMT == S_IFDIR else { throw NativeUpdateFailure.integrity }
        return (info.st_dev, info.st_ino)
    }

    private static func exchange(
        _ parent: Int32, _ installed: String, _ transaction: Int32, _ staged: String,
        _ installedIdentity: (dev_t, ino_t), _ stagedIdentity: (dev_t, ino_t)
    ) throws {
        guard try identity(parent, installed) == installedIdentity,
              try identity(transaction, staged) == stagedIdentity else { throw NativeUpdateFailure.integrity }
        guard renameatx_np(parent, installed, transaction, staged, UInt32(RENAME_SWAP)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func readRegularFile(_ url: URL, limit: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw NativeUpdateFailure.integrity }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= limit else { throw NativeUpdateFailure.integrity }
        let bytes = try file.read(upToCount: limit + 1) ?? Data()
        guard bytes.count == info.st_size else { throw NativeUpdateFailure.integrity }
        return bytes
    }

    private static func spawn(_ path: String, _ args: [String], output: Any = FileHandle.nullDevice) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private static func wait(seconds: TimeInterval, until predicate: () -> Bool) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if predicate() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return predicate()
    }

    private static func outputReceipt(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        return try file.read(upToCount: 128) ?? Data()
    }

    private static func launchAndConfirm(_ executable: URL, directory: URL) throws {
        let token = UUID().uuidString
        let receipt = directory.appendingPathComponent("startup-\(token)")
        let fd = open(receipt.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw NativeUpdateFailure.integrity }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? output.close() }
        let process = try spawn(executable.path, ["--confirm-update-startup", token], output: output)
        let expected = Data("HD2_UPDATE_READY \(token)\n".utf8)
        var receiptTime: TimeInterval?
        var confirmed = false
        _ = wait(seconds: 25) {
            guard process.isRunning else { return true }
            if let bytes = try? outputReceipt(receipt), bytes == expected {
                let now = ProcessInfo.processInfo.systemUptime
                if let receiptTime, now - receiptTime >= 1 {
                    confirmed = true
                    return true
                }
                if receiptTime == nil { receiptTime = now }
            }
            return false
        }
        guard confirmed && process.isRunning else {
            if process.isRunning {
                process.terminate()
                if !wait(seconds: 3, until: { !process.isRunning }) { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
            throw POSIXError(.ETIMEDOUT)
        }
    }
}
