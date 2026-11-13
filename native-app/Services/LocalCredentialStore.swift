import Foundation
import CryptoKit
import Darwin

protocol SavedCredentialStore {
    func load(scope: String, kind: CredentialKind) throws -> String?
    func save(_ secret: String, scope: String, kind: CredentialKind) throws
    func remove(scope: String, kind: CredentialKind) throws
}

enum LocalCredentialStoreError: Error { case unsafeStorage, io, damaged }

/// Installation-local AES-GCM storage, outside the App bundle. No Keychain APIs.
/// The random installation key and ciphertext are protected by owner-only POSIX
/// permissions. This does not defend against software already running as this user.
final class LocalCredentialStore: SavedCredentialStore {
    let root: URL
    init(root: URL) { self.root = root.standardizedFileURL }
    static func production() -> LocalCredentialStore {
        LocalCredentialStore(root: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Helldivers2FXLauncher/native/saved-credentials-v1", isDirectory: true))
    }
    private func name(_ scope: String, _ kind: CredentialKind) -> String {
        SHA256.hash(data: Data(("v1|" + scope + "|" + kind.rawValue).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func validate(_ fd: Int32, directory: Bool = false) throws -> stat {
        var s = stat()
        guard fstat(fd, &s) == 0, s.st_uid == getuid(), s.st_mode & 0o077 == 0,
              (s.st_mode & S_IFMT) == (directory ? S_IFDIR : S_IFREG), directory || s.st_nlink == 1 else {
            throw LocalCredentialStoreError.unsafeStorage
        }
        return s
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let dir = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard dir >= 0 else { throw LocalCredentialStoreError.unsafeStorage }
        defer { close(dir) }; _ = try validate(dir, directory: true)
        let fd = open(root.appendingPathComponent(".lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw LocalCredentialStoreError.io }
        defer { close(fd) }; _ = try validate(fd)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard (errno == EWOULDBLOCK || errno == EAGAIN), ProcessInfo.processInfo.systemUptime < deadline else { throw LocalCredentialStoreError.io }
            usleep(10_000)
        }
        defer { _ = flock(fd, LOCK_UN) }
        return try operation()
    }
    private func read(_ url: URL) throws -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 { if errno == ENOENT { return nil }; throw LocalCredentialStoreError.unsafeStorage }
        defer { close(fd) }; let s = try validate(fd)
        guard s.st_size >= 0, s.st_size <= 16_384 else { throw LocalCredentialStoreError.damaged }
        let length = Int(s.st_size)
        var bytes = [UInt8](repeating: 0, count: length); var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), length - offset) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw LocalCredentialStoreError.io }; offset += n
        }
        return Data(bytes)
    }
    private func syncDirectory() throws {
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw LocalCredentialStoreError.io }
        defer { close(fd) }; _ = try validate(fd, directory: true)
        guard fsync(fd) == 0 else { throw LocalCredentialStoreError.io }
    }
    private func write(_ data: Data, to url: URL) throws {
        _ = try read(url) // Reject symlinks, hard links, foreign owners and loose modes.
        let temporary = root.appendingPathComponent(UUID().uuidString + ".tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw LocalCredentialStoreError.io }
        defer { close(fd); _ = unlink(temporary.path) }
        _ = try validate(fd); var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), data.count - offset) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw LocalCredentialStoreError.io }; offset += n
        }
        guard fsync(fd) == 0, rename(temporary.path, url.path) == 0 else { throw LocalCredentialStoreError.io }
        try syncDirectory()
    }
    private func erase(_ url: URL) throws {
        _ = try read(url)
        if unlink(url.path) == 0 { try syncDirectory() }
        else if errno != ENOENT { throw LocalCredentialStoreError.io }
    }
    private func key(create: Bool) throws -> SymmetricKey? {
        let url = root.appendingPathComponent("installation.key")
        if let data = try read(url) {
            guard data.count == 32 else { throw LocalCredentialStoreError.damaged }
            return SymmetricKey(data: data)
        }
        guard create else { return nil }
        let key = SymmetricKey(size: .bits256)
        try write(key.withUnsafeBytes { Data($0) }, to: url)
        return key
    }
    func load(scope: String, kind: CredentialKind) throws -> String? {
        try locked {
            let name = name(scope, kind)
            if try read(root.appendingPathComponent(name + ".blocked")) != nil { return nil }
            guard let sealed = try read(root.appendingPathComponent(name + ".sealed")) else { return nil }
            guard let key = try key(create: false) else { throw LocalCredentialStoreError.damaged }
            let bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: Data(name.utf8))
            guard let value = String(data: bytes, encoding: .utf8), !value.isEmpty else { throw LocalCredentialStoreError.damaged }
            return value
        }
    }
    func save(_ secret: String, scope: String, kind: CredentialKind) throws {
        guard !secret.isEmpty, secret.utf8.count <= 8_192 else { throw LocalCredentialStoreError.damaged }
        try locked {
            let name = name(scope, kind)
            guard let key = try key(create: true), let sealed = try AES.GCM.seal(Data(secret.utf8), using: key, authenticating: Data(name.utf8)).combined else { throw LocalCredentialStoreError.damaged }
            try write(sealed, to: root.appendingPathComponent(name + ".sealed"))
            try erase(root.appendingPathComponent(name + ".blocked"))
        }
    }
    func remove(scope: String, kind: CredentialKind) throws {
        try locked {
            let name = name(scope, kind)
            // A durable non-secret tombstone prevents reuse even if deletion fails.
            try write(Data(), to: root.appendingPathComponent(name + ".blocked"))
            try erase(root.appendingPathComponent(name + ".sealed"))
        }
    }
}
