import Foundation
import Darwin

/// A bounded, redaction-safe failure surfaced to the UI by stable code.
struct CoreError: Error, Sendable {
    let code: String
    let details: [String: JSONValue]
    init(_ code: String, _ details: [String: JSONValue] = [:]) {
        self.code = code
        self.details = details
    }
}

enum CoreLimits {
    static let maxSmallFile = 256 * 1024
    static let maxResourceFile = 2 * 1024 * 1024
    static let maxBundleExecutable = 512 * 1024 * 1024
    static let maxOutput = 1_048_576
    static let maxScanEntries = 2048
}

enum CoreClock {
    static func stamp(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }
    static var monotonic: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// Cooperative cancellation plus a hard deadline for blocking subprocess work.
final class CoreContext: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    let deadline: TimeInterval
    init(timeout: TimeInterval) { deadline = CoreClock.monotonic + max(0.05, timeout) }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func check() throws {
        if isCancelled { throw CoreError("CANCELLED") }
        if CoreClock.monotonic >= deadline { throw CoreError("TIMEOUT") }
    }
}

enum CoreJSON {
    static func value(_ any: Any?) -> JSONValue {
        switch any {
        case let value as String: return .string(value)
        // NSNumber must precede Bool: 0/1 bridge to Bool and would corrupt numbers.
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            return .number(value.doubleValue)
        case let value as Bool: return .bool(value)
        case let value as Int: return .number(Double(value))
        case let value as Double: return .number(value)
        case let value as [String: Any]: return .object(value.mapValues { CoreJSON.value($0) })
        case let value as [Any]: return .array(value.map { CoreJSON.value($0) })
        case is NSNull, nil: return .null
        default: return .string(String(describing: any!))
        }
    }

    static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }

    static func pretty(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

enum CoreHash {
    static func sha256(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { raw in
            if #available(macOS 10.15, *) {
                var context = SHA256Context()
                sha256_init(&context)
                sha256_update(&context, raw.bindMemory(to: UInt8.self).baseAddress, data.count)
                sha256_final(&context, &digest)
            }
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Streams the file so a large FX executable is never loaded whole.
    static func sha256File(_ url: URL, limit: Int = CoreLimits.maxBundleExecutable) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var context = SHA256Context()
        sha256_init(&context)
        var total = 0
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            total += chunk.count
            if total > limit { throw CoreError("OUTPUT_LIMIT") }
            chunk.withUnsafeBytes { raw in
                if let base = raw.bindMemory(to: UInt8.self).baseAddress {
                    sha256_update(&context, base, chunk.count)
                }
            }
        }
        var digest = [UInt8](repeating: 0, count: 32)
        sha256_final(&context, &digest)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func digestFile(_ base: URL, relative: String, limit: Int = CoreLimits.maxResourceFile) -> (String?, String) {
        var path = base
        for part in relative.split(separator: "/") {
            path.appendPathComponent(String(part))
            if FileManager.default.isSymbolicLink(atPath: path.path) { return (nil, "unsafe_path") }
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            guard let type = attributes[.type] as? FileAttributeType, type == .typeRegular else { return (nil, "invalid_file") }
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            if size > limit { return (nil, "invalid_file") }
            let before = try FileManager.default.attributesOfItem(atPath: path.path)
            let hash = try sha256File(path, limit: limit)
            let after = try FileManager.default.attributesOfItem(atPath: path.path)
            func fingerprint(_ values: [FileAttributeKey: Any]) -> String {
                [values[.size], values[.systemFileNumber], values[.modificationDate], values[.creationDate]]
                    .map { String(describing: $0) }.joined(separator: "|")
            }
            if fingerprint(before) != fingerprint(after) { return (nil, "file_changed") }
            return (hash, "present")
        } catch let error as NSError {
            if error.code == NSFileReadNoSuchFileError { return (nil, "missing") }
            if error.code == NSFileReadUnknownError { return (nil, "unreadable") }
            return (nil, "unreadable")
        }
    }
}

extension FileManager {
    func isSymbolicLink(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }
}

enum CoreFS {
    static func home() -> URL { FileManager.default.homeDirectoryForCurrentUser }
    static func appSupport() -> URL {
        if let root = ProcessInfo.processInfo.environment["HD2FX_NATIVE_TEST_ROOT"], !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true)
        }
        return home().appendingPathComponent("Library/Application Support/Helldivers2FXLauncher", isDirectory: true)
    }
    static func nativeData() -> URL { appSupport().appendingPathComponent("native", isDirectory: true) }

    static func isRegularExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    static func noSymlink(_ url: URL) -> Bool {
        var current = url
        for _ in 0..<8 {
            if FileManager.default.isSymbolicLink(atPath: current.path) { return false }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || parent.path == "/" { break }
            current = parent
        }
        return true
    }

    static func ensurePrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CoreError("UNSAFE_PATH")
        }
        if FileManager.default.isSymbolicLink(atPath: url.path) { throw CoreError("UNSAFE_PATH") }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.intValue ?? -1
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        if owner != Int(getuid()) || (mode & 0o022) != 0 { throw CoreError("UNSAFE_PATH") }
    }

    /// Writes only through an app-owned, non-symlink temporary file in the same directory.
    static func atomicWrite(_ data: Data, to url: URL, mode: Int = 0o600) throws {
        let directory = url.deletingLastPathComponent()
        try ensurePrivateDirectory(directory)
        if FileManager.default.isSymbolicLink(atPath: url.path) { throw CoreError("UNSAFE_PATH") }
        let temporary = directory.appendingPathComponent(".native-\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(mode))
        guard fd >= 0 else { throw CoreError("UNSAFE_PATH") }
        do {
            try data.withUnsafeBytes { raw in
                var offset = 0
                while offset < data.count {
                    let written = write(fd, raw.baseAddress!.advanced(by: offset), data.count - offset)
                    if written <= 0 { throw CoreError("WRITE_FAILED") }
                    offset += written
                }
            }
            fsync(fd)
            close(fd)
            if rename(temporary.path, url.path) != 0 { throw CoreError("WRITE_FAILED") }
        } catch {
            close(fd)
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    static func backupFile(_ url: URL, directory: URL, label: String) throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try ensurePrivateDirectory(directory)
        let target = directory.appendingPathComponent("\(label)-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: url, to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return target
    }
}

/// Advisory inter-process lock; never unlinks the file or kills a stale owner.
final class CoreFileLock {
    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }
    static func acquire(_ url: URL, createDirectory: Bool = true) throws -> CoreFileLock {
        let directory = url.deletingLastPathComponent()
        if createDirectory { try CoreFS.ensurePrivateDirectory(directory) }
        let fd = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CoreError("UNSAFE_PATH") }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else {
            close(fd); throw CoreError("UNSAFE_PATH")
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { close(fd); throw CoreError("BUSY") }
        return CoreFileLock(descriptor: fd)
    }
    func release() { flock(descriptor, LOCK_UN); close(descriptor) }
    deinit { release() }
}

struct CoreProcessResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

enum CoreProcess {
    /// Runs a fixed absolute binary with an explicit argument vector; never a shell string.
    static func run(_ executable: String, _ arguments: [String], input: String? = nil,
                    timeout: TimeInterval = 10, environment: [String: String]? = nil,
                    context: CoreContext? = nil) throws -> CoreProcessResult {
        try context?.check()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment } else {
            process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
        }
        let output = Pipe(), errors = Pipe(), stdin = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        do { try process.run() } catch { throw CoreError("PROCESS_UNAVAILABLE", ["binary": .string(URL(fileURLWithPath: executable).lastPathComponent)]) }
        if let input, let data = input.data(using: .utf8) { try? stdin.fileHandleForWriting.write(contentsOf: data) }
        try? stdin.fileHandleForWriting.close()
        var handles = [output.fileHandleForReading, errors.fileHandleForReading]
        for handle in handles {
            let flags = fcntl(handle.fileDescriptor, F_GETFL)
            _ = fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK)
        }
        var out = Data(), err = Data()
        let deadline = min(context?.deadline ?? .greatestFiniteMagnitude, CoreClock.monotonic + timeout)
        var timedOut = false
        func drain(_ handle: FileHandle, into buffer: inout Data) throws {
            var chunk = [UInt8](repeating: 0, count: 8192)
            for _ in 0..<32 {
                let count = read(handle.fileDescriptor, &chunk, chunk.count)
                if count == 0 { return }
                if count < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { return }
                    if errno == EINTR { continue }
                    return
                }
                if buffer.count + count > CoreLimits.maxOutput { throw CoreError("OUTPUT_LIMIT") }
                buffer.append(contentsOf: chunk.prefix(count))
            }
        }
        while true {
            if context?.isCancelled == true { process.terminate(); throw CoreError("CANCELLED") }
            if CoreClock.monotonic >= deadline { timedOut = true; process.terminate(); break }
            try drain(output.fileHandleForReading, into: &out)
            try drain(errors.fileHandleForReading, into: &err)
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        // Final bounded drain after exit; a full pipe must not hide the status.
        for _ in 0..<3 {
            try drain(output.fileHandleForReading, into: &out)
            try drain(errors.fileHandleForReading, into: &err)
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if timedOut {
            let grace = CoreClock.monotonic + 1.0
            while process.isRunning && CoreClock.monotonic < grace { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        for handle in handles { try? handle.close() }
        handles.removeAll()
        return CoreProcessResult(status: timedOut ? -1 : process.terminationStatus,
                                 stdout: String(decoding: out, as: UTF8.self),
                                 stderr: String(decoding: err, as: UTF8.self), timedOut: timedOut)
    }

    static func psCommandTable(context: CoreContext? = nil) throws -> String {
        let result = try run("/bin/ps", ["-ww", "-axo", "pid=,ppid=,lstart=,comm="], timeout: 8, context: context)
        guard result.status == 0 else { throw CoreError("PROCESS_UNAVAILABLE") }
        return result.stdout
    }

    static func processNames(context: CoreContext? = nil) throws -> [String] {
        let result = try run("/bin/ps", ["-axo", "comm="], timeout: 5, context: context)
        guard result.status == 0 else { throw CoreError("PROCESS_UNAVAILABLE") }
        return result.stdout.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

enum CoreRedaction {
    static let secretKeys = ["password", "passphrase", "token", "secret", "authorization", "private_key", "api_key"]

    static func scrub(_ text: String, secrets: [String] = []) -> String {
        var value = text
        for secret in secrets where !secret.isEmpty {
            value = value.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        value = value.replacingOccurrences(of: #"(?i)(password|passphrase|token|authorization)\s*[:=]\s*\S+"#, with: "$1=[REDACTED]", options: .regularExpression)
        value = value.replacingOccurrences(of: #"/Users/[^/\s]+"#, with: "~/…", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])"#, with: "[IP]", options: .regularExpression)
        if value.count > 4000 { value = String(value.prefix(4000)) }
        return value
    }

    static func container(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            return .object(object.filter { key, _ in !secretKeys.contains { key.lowercased().contains($0) } }.mapValues { container($0) })
        case .array(let rows): return .array(rows.prefix(200).map { container($0) })
        case .string(let text): return .string(scrub(text))
        default: return value
        }
    }

    static func containsSecret(_ text: String) -> Bool {
        text.range(of: #"(?i)(password|passphrase|token|authorization|private[_-]?key|api[_-]?key)\s*[:=]\s*\S{3,}"#, options: .regularExpression) != nil
    }
}

func localizedTechnical(_ value: String) -> String { value.isEmpty ? "unknown" : value }

// MARK: - SHA-256 (CommonCrypto-free, stable on macOS 14+)

struct SHA256Context {
    var state: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                           0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    var buffer = [UInt8]()
    var length: UInt64 = 0
}

private let sha256K: [UInt32] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]

func sha256_init(_ context: inout SHA256Context) {
    context.state = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                     0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    context.buffer.removeAll(keepingCapacity: true)
    context.length = 0
}

private func sha256Compress(_ context: inout SHA256Context, _ block: [UInt8]) {
    var w = [UInt32](repeating: 0, count: 64)
    for i in 0..<16 {
        let j = i * 4
        w[i] = (UInt32(block[j]) << 24) | (UInt32(block[j + 1]) << 16) | (UInt32(block[j + 2]) << 8) | UInt32(block[j + 3])
    }
    for i in 16..<64 {
        let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
        let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
        w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
    }
    var a = context.state[0], b = context.state[1], c = context.state[2], d = context.state[3]
    var e = context.state[4], f = context.state[5], g = context.state[6], h = context.state[7]
    for i in 0..<64 {
        let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
        let ch = (e & f) ^ (~e & g)
        let temp1 = h &+ s1 &+ ch &+ sha256K[i] &+ w[i]
        let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
        let maj = (a & b) ^ (a & c) ^ (b & c)
        let temp2 = s0 &+ maj
        h = g; g = f; f = e; e = d &+ temp1
        d = c; c = b; b = a; a = temp1 &+ temp2
    }
    context.state[0] = context.state[0] &+ a
    context.state[1] = context.state[1] &+ b
    context.state[2] = context.state[2] &+ c
    context.state[3] = context.state[3] &+ d
    context.state[4] = context.state[4] &+ e
    context.state[5] = context.state[5] &+ f
    context.state[6] = context.state[6] &+ g
    context.state[7] = context.state[7] &+ h
}

private func rotr(_ value: UInt32, _ amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
}

func sha256_update(_ context: inout SHA256Context, _ bytes: UnsafePointer<UInt8>?, _ count: Int) {
    guard let bytes, count > 0 else { return }
    context.length &+= UInt64(count)
    var offset = 0
    if !context.buffer.isEmpty {
        let needed = min(64 - context.buffer.count, count)
        context.buffer.append(contentsOf: UnsafeBufferPointer(start: bytes, count: needed))
        offset += needed
        if context.buffer.count == 64 {
            sha256Compress(&context, context.buffer)
            context.buffer.removeAll(keepingCapacity: true)
        }
    }
    while offset + 64 <= count {
        let block = Array(UnsafeBufferPointer(start: bytes + offset, count: 64))
        sha256Compress(&context, block)
        offset += 64
    }
    if offset < count {
        context.buffer.append(contentsOf: UnsafeBufferPointer(start: bytes + offset, count: count - offset))
    }
}

func sha256_final(_ context: inout SHA256Context, _ digest: inout [UInt8]) {
    let bitLength = context.length &* 8
    context.buffer.append(0x80)
    while context.buffer.count % 64 != 56 { context.buffer.append(0) }
    for shift in stride(from: 56, through: 0, by: -8) {
        context.buffer.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
    }
    var index = 0
    while index < context.buffer.count {
        sha256Compress(&context, Array(context.buffer[index..<index + 64]))
        index += 64
    }
    digest = [UInt8](repeating: 0, count: 32)
    for (i, value) in context.state.enumerated() {
        digest[i * 4] = UInt8((value >> 24) & 0xff)
        digest[i * 4 + 1] = UInt8((value >> 16) & 0xff)
        digest[i * 4 + 2] = UInt8((value >> 8) & 0xff)
        digest[i * 4 + 3] = UInt8(value & 0xff)
    }
}


// Tracks owned native workers during AppKit's nested termination loop.
enum BridgeWorkerStatus {
    private static let lock = NSLock()
    private static var count = 0
    static func enter() { lock.lock(); count += 1; lock.unlock() }
    static func leave() { lock.lock(); count -= 1; lock.unlock() }
    static var isActive: Bool { lock.lock(); defer { lock.unlock() }; return count > 0 }
}

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
