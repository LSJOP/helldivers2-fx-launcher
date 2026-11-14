// Operator-only Ed25519 signing. Never linked into the App; no Keychain access.
import Foundation
import CryptoKit
import Darwin

enum SigningError: Error { case usage, unsafeFile, size }
func privateKey(at path: String) throws -> Curve25519.Signing.PrivateKey {
    let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw SigningError.unsafeFile }
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? file.close() }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
          info.st_mode & 0o777 == 0o600, info.st_uid == getuid(), info.st_size == 32 else { throw SigningError.unsafeFile }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: file.readToEnd() ?? Data())
}
let args = CommandLine.arguments
 do {
    guard args.count >= 3 else { throw SigningError.usage }
    switch args[1] {
    case "generate":
        guard args.count == 3 else { throw SigningError.usage }
        let key = Curve25519.Signing.PrivateKey()
        let fd = open(args[2], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SigningError.unsafeFile }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try file.write(contentsOf: key.rawRepresentation); try file.synchronize(); try file.close()
        print(key.publicKey.rawRepresentation.base64EncodedString())
    case "public":
        guard args.count == 3 else { throw SigningError.usage }
        print(try privateKey(at: args[2]).publicKey.rawRepresentation.base64EncodedString())
    case "sign":
        guard args.count == 4 else { throw SigningError.usage }
        let key = try privateKey(at: args[2])
        let fd = open(args[3], O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SigningError.unsafeFile }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= 536_870_912 else { throw SigningError.size }
        print(try key.signature(for: file.readToEnd() ?? Data()).base64EncodedString())
    default: throw SigningError.usage
    }
} catch {
    fputs("Signing failed (usage, permissions, input or key validation).\n", stderr)
    exit(1)
}
