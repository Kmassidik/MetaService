import Foundation
import MSCore

/// One key as the store keeps it. The secret is not here, only its hash.
public struct StoredApiKey: Equatable, Sendable {
    public let id: String
    public let team: String
    /// `msb_ab12cd34`, for display.
    public let prefix: String
    /// SHA-256 of the secret, in hex.
    public let secretHash: String
    /// Nil while the key may be used; the moment it was revoked otherwise.
    public let revokedAt: Date?

    public init(id: String, team: String, prefix: String, secretHash: String, revokedAt: Date?) {
        self.id = id
        self.team = team
        self.prefix = prefix
        self.secretHash = secretHash
        self.revokedAt = revokedAt
    }
}

/// Why a presented key is refused. The public API answers 401 either way, but the two are told apart in the panel and in tests.
public struct ApiKeyRefusal: Error, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public static let unknown = ApiKeyRefusal(code: ApiKeyCheck.unknownCode, message: "The API key is missing or not one of ours.")
    public static let revoked = ApiKeyRefusal(code: ApiKeyCheck.revokedCode, message: "This API key was revoked.")
}

/// The answer to a presented key: the key it belongs to, or the distinct reason it is refused.
public enum ApiKeyCheck: Equatable, Sendable {
    case accepted(StoredApiKey)
    case unknown
    case revoked

    public static let unknownCode = "invalid_key"
    public static let revokedCode = "revoked_key"

    public var key: StoredApiKey? {
        guard case .accepted(let key) = self else { return nil }
        return key
    }

    /// The plain refusal, for a caller that answers 401. Nil when the key is accepted.
    public var refusal: ApiKeyRefusal? {
        switch self {
        case .accepted: return nil
        case .unknown: return .unknown
        case .revoked: return .revoked
        }
    }
}

/// Checks a presented key. Pure: the store's lookup is passed in, so the whole rule is testable without a database.
///
/// The prefix is not secret, so finding the row by it may take a normal comparison. The secret is compared through its
/// SHA-256 in constant time. A revoked key is refused before its secret is checked, and an unknown prefix says nothing
/// about whether a similar key exists.
public enum ApiKeyGate {
    public static func check(_ presented: String, lookup: (String) -> StoredApiKey?) -> ApiKeyCheck {
        guard let parts = ApiKeyRules.parse(presented) else { return .unknown }
        return check(parts: parts, lookup: lookup)
    }

    public static func check(parts: ApiKeyRules.Parts, lookup: (String) -> StoredApiKey?) -> ApiKeyCheck {
        guard let stored = lookup(parts.prefix) else { return .unknown }
        return check(parts: parts, against: stored)
    }

    public static func check(parts: ApiKeyRules.Parts, against stored: StoredApiKey) -> ApiKeyCheck {
        guard stored.revokedAt == nil else { return .revoked }
        guard Tokens.constantTimeEqual(ApiKeyRules.hash(secret: parts.secret), stored.secretHash) else { return .unknown }
        return .accepted(stored)
    }
}
