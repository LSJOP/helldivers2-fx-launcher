import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4, let publicKey = Data(base64Encoded: arguments[2]) else { fatalError("Invalid verification arguments") }
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let manifest = try Data(contentsOf: directory.appendingPathComponent("update-manifest.json"))
let encoded = try String(contentsOf: directory.appendingPathComponent("update-manifest.sig"), encoding: .utf8)
guard manifest.count <= 65_536,
      let signature = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
      let object = try JSONSerialization.jsonObject(with: manifest) as? [String: Any],
      let schema = object["schema"] as? Int, [2, 3].contains(schema) else { fatalError("Invalid signatures") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
guard key.isValidSignature(signature, for: manifest) else { fatalError("Release Ed25519 manifest signature verification failed") }
if schema == 2 {
    guard let archiveSignature = object["archiveEdSignature"] as? String,
          let archiveBytes = Data(base64Encoded: archiveSignature),
          key.isValidSignature(archiveBytes, for: try Data(contentsOf: directory.appendingPathComponent(arguments[3]), options: .mappedIfSafe))
    else { fatalError("Release Ed25519 archive signature verification failed") }
}
