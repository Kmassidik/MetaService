import CryptoKit
import Foundation

/// A WireGuard key pair, in the text form `wg` and the config files use (base64 of the 32 raw bytes).
public struct WireGuardKeyPair: Equatable, Sendable {
    public let privateKey: String
    public let publicKey: String

    public static func generate() -> WireGuardKeyPair {
        make(Curve25519.KeyAgreement.PrivateKey())
    }

    public static func make(_ key: Curve25519.KeyAgreement.PrivateKey) -> WireGuardKeyPair {
        WireGuardKeyPair(privateKey: key.rawRepresentation.base64EncodedString(), publicKey: key.publicKey.rawRepresentation.base64EncodedString())
    }

    /// The public key for a private key in text form, or nil when the text is not a valid key.
    public static func publicKey(forPrivate text: String) -> String? {
        guard let data = Data(base64Encoded: text), let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) else { return nil }
        return key.publicKey.rawRepresentation.base64EncodedString()
    }

    public static func isValidPublicKey(_ text: String) -> Bool {
        guard let data = Data(base64Encoded: text) else { return false }
        return data.count == 32 && text.count == 44
    }
}
