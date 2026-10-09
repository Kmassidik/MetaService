import CryptoKit
import Foundation

public enum SecretBoxError: Error, Equatable {
    case badKeyFile
    case looseKeyFile
    case cannotOpen
}

/// Encrypts small secrets at rest (AES-GCM). The key lives in its own file, mode 600, outside the database,
/// so a copy of the database alone does not give the secrets away.
public struct SecretBox: Sendable {
    private let key: SymmetricKey
    public static let keyBytes = 32

    public init(keyData: Data) throws {
        guard keyData.count == Self.keyBytes else { throw SecretBoxError.badKeyFile }
        key = SymmetricKey(data: keyData)
    }

    /// Reads the key file, or makes a new random one the first time. A file other users can read is refused.
    public static func loadOrCreate(path: String) throws -> SecretBox {
        guard FileManager.default.fileExists(atPath: path) else {
            var bytes = [UInt8](repeating: 0, count: keyBytes)
            guard SecRandomCopyBytes(kSecRandomDefault, keyBytes, &bytes) == errSecSuccess else { throw SecretBoxError.badKeyFile }
            guard FileManager.default.createFile(atPath: path, contents: Data(Tokens.base64url(Data(bytes)).utf8), attributes: [.posixPermissions: 0o600]) else { throw SecretBoxError.badKeyFile }
            return try SecretBox(keyData: Data(bytes))
        }
        let mode = ((try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? NSNumber)?.intValue ?? 0o777
        guard mode & 0o077 == 0 else { throw SecretBoxError.looseKeyFile }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), let data = decode(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SecretBoxError.badKeyFile }
        return try SecretBox(keyData: data)
    }

    public func seal(_ text: String) throws -> String {
        guard let combined = try AES.GCM.seal(Data(text.utf8), using: key).combined else { throw SecretBoxError.cannotOpen }
        return Tokens.base64url(combined)
    }

    public func open(_ sealed: String) throws -> String {
        guard let data = Self.decode(sealed), let box = try? AES.GCM.SealedBox(combined: data), let plain = try? AES.GCM.open(box, using: key) else { throw SecretBoxError.cannotOpen }
        return String(decoding: plain, as: UTF8.self)
    }

    private static func decode(_ text: String) -> Data? {
        var padded = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        return Data(base64Encoded: padded)
    }
}

public enum ContractVersion {
    /// The version of contract/openapi.yaml. Root and Agents both send it with every reply.
    public static let current = "1.2.0"
}
