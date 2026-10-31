import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4,
      let signature = Data(base64Encoded: CommandLine.arguments[2]),
      let publicData = Data(base64Encoded: CommandLine.arguments[3]) else {
    fputs("usage: verify-update archive signature public-key\n", stderr)
    exit(64)
}
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    guard key.isValidSignature(signature, for: archive) else {
        fputs("Update signature does not match the public key embedded in Light\n", stderr)
        exit(1)
    }
    print("Verified update signature against Light's embedded public key")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
