import CryptoKit
import Foundation
import MSCore

/// A public key that passed every rule, in the form it is stored and later written to a VM's authorized_keys.
public struct ParsedSshKey: Equatable {
    public let type: String
    /// The base64 text of the key. Never logged and never returned to the panel.
    public let blob: String
    public let comment: String
    /// `SHA256:` and the unpadded base64 of the SHA-256 of the key, as `ssh-keygen -lf` prints it.
    public let fingerprint: String

    public init(type: String, blob: String, comment: String, fingerprint: String) {
        self.type = type
        self.blob = blob
        self.comment = comment
        self.fingerprint = fingerprint
    }

    /// The one normalised line: `type blob comment` (no comment: `type blob`).
    public var line: String { comment.isEmpty ? "\(type) \(blob)" : "\(type) \(blob) \(comment)" }
}

/// What an operator may paste as a user's SSH public key. Strict on purpose: the line ends up in a root account's authorized_keys,
/// so options (`command=`, `from=`), a second line, odd characters and keys that are not what they say they are are all refused, never cleaned up.
public enum SshKeyRules {
    public static let maxLineCharacters = 800
    public static let maxCommentCharacters = 64
    public static let maxKeysPerVM = 20
    public static let minRsaBits = 2048
    public static let rsaType = "ssh-rsa"
    public static let allowedTypes: Set<String> = ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", rsaType, "sk-ssh-ed25519@openssh.com"]

    static let optionsMessage = "Options such as command= or from= are not allowed. Paste only the public key itself, starting with its type, for example ssh-ed25519."
    private static let typePrefixes = ["ssh-", "ecdsa-", "sk-"]
    private static let commentCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._@+:-")
    private static let base64Characters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
    private static let firstPrintable: UInt32 = 0x20
    private static let delete: UInt32 = 0x7f
    private static let lengthPrefixBytes = 4
    private static let bitsPerByte = 8
    private static let rsaFieldCount = 3
    private static let rsaModulusField = 2

    public static func parse(_ text: String) throws -> ParsedSshKey {
        try requireOneCleanLine(text)
        let parts = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let type = try requireKeyType(parts[0])
        guard (2...3).contains(parts.count), !parts.contains("") else {
            throw InputError("The key must look like: type, one space, the key, and optionally one space and a short comment. A comment may not contain spaces.")
        }
        let blob = try decodeBlob(parts[1])
        let comment = parts.count == 3 ? parts[2] : ""
        try requireComment(comment)
        let fields = try readFields(blob, declaredType: type)
        try requireRsaStrength(type: type, fields: fields)
        return ParsedSshKey(type: type, blob: parts[1], comment: comment, fingerprint: fingerprint(of: blob))
    }

    public static func fingerprint(of blob: Data) -> String {
        "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    // MARK: the line

    private static func requireOneCleanLine(_ text: String) throws {
        guard text.unicodeScalars.allSatisfy({ $0.value >= firstPrintable && $0.value != delete }) else {
            throw InputError("The key must be a single line with no line breaks or control characters.")
        }
        guard text.count <= maxLineCharacters else { throw InputError("The key is too long: at most \(maxLineCharacters) characters.") }
        guard text.first != " ", text.last != " " else { throw InputError("Remove the spaces at the start or end of the key.") }
    }

    private static func requireKeyType(_ declared: String) throws -> String {
        if allowedTypes.contains(declared) { return declared }
        guard typePrefixes.contains(where: declared.hasPrefix) else { throw InputError(optionsMessage) }
        throw InputError("This key type is not supported. Use ssh-ed25519, ecdsa-sha2-nistp256/384/521, ssh-rsa (2048 bits or more) or sk-ssh-ed25519@openssh.com.")
    }

    private static func requireComment(_ comment: String) throws {
        guard comment.count <= maxCommentCharacters, comment.allSatisfy(commentCharacters.contains) else {
            throw InputError("The comment may only hold letters, digits and . _ @ + : - (at most \(maxCommentCharacters) characters).")
        }
    }

    // MARK: the key itself

    private static func decodeBlob(_ text: String) throws -> Data {
        guard text.allSatisfy(base64Characters.contains), let blob = Data(base64Encoded: text), blob.base64EncodedString() == text else {
            throw InputError("The key part is not valid base64. Paste the whole public key without changes.")
        }
        return blob
    }

    /// Every length-prefixed field of the blob; the first must be the declared type, and nothing may be left over.
    private static func readFields(_ blob: Data, declaredType: String) throws -> [Data] {
        let bytes = [UInt8](blob)
        var fields: [Data] = []
        var offset = 0
        while offset < bytes.count {
            guard offset + lengthPrefixBytes <= bytes.count else { throw damaged }
            let length = bytes[offset..<offset + lengthPrefixBytes].reduce(0) { $0 << bitsPerByte | Int($1) }
            offset += lengthPrefixBytes
            guard length <= bytes.count - offset else { throw damaged }
            fields.append(Data(bytes[offset..<offset + length]))
            offset += length
        }
        guard let first = fields.first, fields.count > 1 else { throw damaged }
        guard String(data: first, encoding: .utf8) == declaredType else {
            throw InputError("The key is not a \(declaredType) key: the type written in front of it does not match the key.")
        }
        return fields
    }

    private static var damaged: InputError { InputError("The key is damaged or cut short. Paste the whole public key without changes.") }

    private static func requireRsaStrength(type: String, fields: [Data]) throws {
        guard type == rsaType else { return }
        guard fields.count == rsaFieldCount else { throw damaged }
        let modulus = [UInt8](fields[rsaModulusField]).drop(while: { $0 == 0 })
        guard let top = modulus.first else { throw damaged }
        let bits = (modulus.count - 1) * bitsPerByte + (bitsPerByte - top.leadingZeroBitCount)
        guard bits >= minRsaBits else { throw InputError("This RSA key is too weak (\(bits) bits). Use at least \(minRsaBits) bits, or an ed25519 key.") }
    }
}
