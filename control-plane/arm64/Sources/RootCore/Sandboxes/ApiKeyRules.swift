import Foundation
import MSCore

/// A sandbox API key is a fixed marker, a short readable prefix, and a random secret:
///
///     msb_ab12cd34_<43 characters of base64url>
///
/// The prefix is what is stored and shown (a key can be recognised in the panel without being kept), and the secret
/// is only ever stored as its SHA-256. The key text itself is returned once, when it is made, and never again.
public enum ApiKeyRules {
    /// Starts every key, so a key pasted by mistake is recognisable, and so a search in logs finds none.
    public static let marker = "msb"
    /// The readable part: lowercase letters and digits only, so it is easy to say out loud and to type.
    public static let prefixCharacters = 8
    /// A secret with 256 bits of randomness, the same as a machine token.
    public static let secretBytes = Tokens.defaultBytes
    public static let separator: Character = "_"
    public static let hashHexCharacters = 64

    private static let prefixAlphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    private static let secretAlphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    private static let base64Group = 3
    private static let base64CharactersPerGroup = 4

    /// How many characters the secret of `secretBytes` takes in unpadded base64url: 43 for 32 bytes.
    public static var secretCharacters: Int {
        let padded = ((secretBytes + base64Group - 1) / base64Group) * base64CharactersPerGroup
        return padded - (base64Group - secretBytes % base64Group) % base64Group
    }

    /// Every character of a whole key: marker, separator, prefix, separator, secret.
    static var keyCharacters: Int { marker.count + 1 + prefixCharacters + 1 + secretCharacters }

    /// The two parts a presented key splits into. The secret is never stored.
    public struct Parts: Equatable {
        /// Includes the marker: `msb_ab12cd34`.
        public let prefix: String
        public let secret: String
    }

    /// A new key: the text to show once, the prefix to keep for display, and the hash to keep for checking.
    public struct Issued: Equatable {
        public let key: String
        public let prefix: String
        public let secretHash: String
    }

    /// Makes a key with a fresh random prefix and secret. A secret may be given for a deterministic test.
    public static func issue(secret: String = Tokens.random(bytes: secretBytes)) -> Issued {
        let prefix = randomPrefix()
        return Issued(key: text(prefix: prefix, secret: secret), prefix: prefix, secretHash: hash(secret: secret))
    }

    /// A fresh readable prefix, marker included.
    public static func randomPrefix() -> String {
        let body = (0..<prefixCharacters).map { _ in prefixAlphabet[Int.random(in: 0..<prefixAlphabet.count)] }
        return marker + String(separator) + String(body)
    }

    /// The key text for a known prefix and secret. The caller is responsible for a well-formed prefix.
    public static func text(prefix: String, secret: String) -> String {
        prefix + String(separator) + secret
    }

    /// Splits a presented key, or nil when it is not shaped like one of ours. Never trims or repairs: a key that is not
    /// exactly the expected length and alphabet is refused.
    public static func parse(_ text: String) -> Parts? {
        let characters = Array(text)
        guard characters.count == keyCharacters else { return nil }
        let prefixStart = marker.count + 1
        let prefixEnd = prefixStart + prefixCharacters
        guard String(characters[0..<marker.count]) == marker, characters[marker.count] == separator, characters[prefixEnd] == separator else { return nil }
        guard characters[prefixStart..<prefixEnd].allSatisfy(prefixAlphabet.contains) else { return nil }
        let secret = String(characters[(prefixEnd + 1)...])
        guard secret.allSatisfy(secretAlphabet.contains) else { return nil }
        return Parts(prefix: String(characters[0..<prefixEnd]), secret: secret)
    }

    /// What is stored for checking: SHA-256 of the secret, in hex. Deterministic, so two hashes can be compared without
    /// keeping the secret anywhere.
    public static func hash(secret: String) -> String {
        Tokens.sha256Hex(secret)
    }
}
