import Foundation

/// The API token an AI client sends as `Authorization: Bearer <token>`. `msk_` and 43 URL-safe base64 characters (256 bits).
/// Only the SHA-256 of the whole text is stored, and the first 8 characters after `msk_` are kept to tell tokens apart. Pure: no database here.
public enum McpToken {
    public static let marker = "msk_"
    public static let secretCharacters = 43
    public static let displayPrefixCharacters = 8
    private static let secretPattern = #/^[A-Za-z0-9_-]{43}$/#

    /// A new token. Shown once, when it is made; the caller stores only `hash(_:)` and `displayPrefix(of:)`.
    public static func make() -> String {
        marker + Tokens.random(bytes: 32)
    }

    /// True for exactly `msk_` plus 43 URL-safe base64 characters. Anything else is refused before the database is asked.
    public static func isWellFormed(_ text: String) -> Bool {
        guard text.hasPrefix(marker) else { return false }
        return String(text.dropFirst(marker.count)).wholeMatch(of: secretPattern) != nil
    }

    /// The first 8 characters after `msk_`: what the panel shows in the token table.
    public static func displayPrefix(of token: String) -> String {
        String(token.dropFirst(marker.count).prefix(displayPrefixCharacters))
    }

    public static func hash(_ token: String) -> String {
        Tokens.sha256Hex(token)
    }
}
