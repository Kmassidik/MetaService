import CryptoKit
import Foundation
import Security

/// Random tokens, their hashes, and a timing-safe comparison. Only hashes are ever stored.
public enum Tokens {
    public static let defaultBytes = 32

    public static func random(bytes: Int = defaultBytes) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer)
        precondition(status == errSecSuccess, "the system random source failed")
        return base64url(Data(buffer))
    }

    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Compares without stopping at the first difference.
    public static func constantTimeEqual(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8), b = Array(right.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
