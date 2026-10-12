import CryptoKit
import Foundation

/// A new Ed25519 key in the formats OpenSSH reads, made in memory: the private key is never written to a file in clear (it is sealed before it is stored).
public enum OpenSshKey {
    public struct Pair {
        public let privateKey: String
        public let publicKey: String
    }

    private static let keyType = "ssh-ed25519"
    private static let magic = Array("openssh-key-v1".utf8) + [0]
    private static let blockSize = 8
    private static let lineWidth = 70

    public static func generateEd25519(comment: String) -> Pair {
        let key = Curve25519.Signing.PrivateKey()
        return Pair(privateKey: privateText(seed: key.rawRepresentation, publicKey: key.publicKey.rawRepresentation, comment: comment),
                    publicKey: "\(keyType) \(publicBlob(key.publicKey.rawRepresentation).base64EncodedString()) \(comment)")
    }

    /// The public key line for a private key text made here.
    static func publicBlob(_ publicKey: Data) -> Data {
        string(Data(keyType.utf8)) + string(publicKey)
    }

    private static func privateText(seed: Data, publicKey: Data, comment: String) -> String {
        let check = UInt32.random(in: 0...UInt32.max)
        var inner = uint32(check) + uint32(check) + string(Data(keyType.utf8)) + string(publicKey) + string(seed + publicKey) + string(Data(comment.utf8))
        var pad: UInt8 = 1
        while inner.count % blockSize != 0 { inner.append(pad); pad += 1 }
        let body = Data(magic) + string(Data("none".utf8)) + string(Data("none".utf8)) + string(Data()) + uint32(1) + string(publicBlob(publicKey)) + string(inner)
        let encoded = body.base64EncodedString()
        let lines = stride(from: 0, to: encoded.count, by: lineWidth).map { index -> String in
            let start = encoded.index(encoded.startIndex, offsetBy: index)
            return String(encoded[start..<encoded.index(start, offsetBy: min(lineWidth, encoded.count - index))])
        }
        return (["-----BEGIN OPENSSH PRIVATE KEY-----"] + lines + ["-----END OPENSSH PRIVATE KEY-----"]).joined(separator: "\n") + "\n"
    }

    private static func uint32(_ value: UInt32) -> Data { Data([UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]) }
    private static func string(_ data: Data) -> Data { uint32(UInt32(data.count)) + data }
}
