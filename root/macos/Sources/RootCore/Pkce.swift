import CryptoKit
import Foundation

public enum Pkce {
    /// S256 code challenge for a verifier (RFC 7636).
    public static func challenge(for verifier: String) -> String {
        Tokens.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}
