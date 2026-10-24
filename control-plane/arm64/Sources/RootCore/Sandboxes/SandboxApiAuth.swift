import Foundation

/// The headers the sandbox API looks at, taken out of the request so the rule can be read (and tested) without HTTP.
public struct SandboxApiHeaders: Equatable, Sendable {
    /// `Authorization`, as it came.
    public let authorization: String?
    /// `X-API-Key` (the SDK's own spelling is `X-API-KEY`; header names are not case-sensitive).
    public let apiKey: String?
    /// Whether the request carried any `Cookie` header at all.
    public let hasCookies: Bool

    public init(authorization: String?, apiKey: String?, hasCookies: Bool) {
        self.authorization = authorization
        self.apiKey = apiKey
        self.hasCookies = hasCookies
    }
}

/// How the public API recognises its caller. Two header forms are accepted, because E2B's SDK sends `X-API-Key` and plain
/// HTTP callers often send `Authorization: Bearer`; nothing else is.
///
/// A request that carries cookies is refused even when it also carries a good key. The panel's session cookie is the
/// confused-deputy case: a browser (or a page on another site, or a link in an email) can make a request that arrives with
/// the operator's session attached, and the last thing a sandbox API may do is act on a browser's cookie as if it were a
/// program's key. The SDK never sends a cookie, so nothing legitimate is lost.
public enum SandboxApiAuth {
    public static let bearerPrefix = "Bearer "
    public static let apiKeyHeader = "X-API-Key"
    /// A key is `msb_<8>_<43>`, 57 characters. Anything much longer is not one of ours and is not hashed.
    public static let maximumKeyCharacters = 200

    /// The key this request presents, or the refusal. The key text is returned only to be checked and is never logged.
    public static func presentedKey(_ headers: SandboxApiHeaders) throws -> String {
        guard !headers.hasCookies else { throw SandboxApiFailure.sessionCookie }
        let bearer = headers.authorization.flatMap(bearerToken)
        switch (headers.apiKey, bearer) {
        case (nil, nil):
            throw SandboxApiFailure.missingKey
        case (.some(let key), nil), (nil, .some(let key)):
            return try usable(key)
        case (.some(let key), .some(let other)):
            // Two different keys say nothing about which one is meant, and checking either would be a guess.
            guard key == other else { throw SandboxApiFailure.missingKey }
            return try usable(key)
        }
    }

    /// The token of a `Bearer` header, nil when the header is something else (Basic, a bare token, an empty value).
    static func bearerToken(_ header: String) -> String? {
        guard header.hasPrefix(bearerPrefix), header.count <= maximumKeyCharacters + bearerPrefix.count else { return nil }
        return String(header.dropFirst(bearerPrefix.count))
    }

    private static func usable(_ key: String) throws -> String {
        guard !key.isEmpty, key.count <= maximumKeyCharacters else { throw SandboxApiFailure.missingKey }
        return key
    }
}
