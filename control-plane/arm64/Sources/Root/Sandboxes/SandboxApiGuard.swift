import Foundation
import Hummingbird
import HTTPTypes
import RootCore
import RootStore

/// The public API's own guard: an API key in a header, and nothing else. It never reads the operator's session cookie or CSRF
/// header, and it does not check the Host (the API answers on its own name, which 5c puts in front of it).
///
/// The key is checked by `ApiKeyStore.authenticate`, which finds the row by prefix and compares the SHA-256 in constant time
/// (`ApiKeyGate`). The key text is never logged, never put in a message and never stored.
struct SandboxApiGuard {
    let services: Services

    static let badKeyLimit = 10
    static let badKeyWindow: TimeInterval = 60
    static let apiKeyHeader = HTTPField.Name(SandboxApiAuth.apiKeyHeader)!

    /// The key's team, after every check. Throws `SandboxApiFailure` (401 when the key is missing, wrong or revoked, 429 when
    /// this address has sent too many bad ones).
    func caller(_ request: Request, context: RootContext) throws -> StoredApiKey {
        guard !services.throttle.isFull(Self.badKeyKey(context), limit: Self.badKeyLimit) else { throw SandboxApiFailure.tooMany }
        let presented = try SandboxApiAuth.presentedKey(Self.headers(of: request))
        do {
            return try services.apiKeys.authenticate(presented, now: services.clock.now)
        } catch let refusal as ApiKeyRefusal {
            _ = services.throttle.allow(Self.badKeyKey(context), limit: Self.badKeyLimit, seconds: Self.badKeyWindow)
            throw refusal.code == ApiKeyCheck.revokedCode ? SandboxApiFailure.revokedKey : SandboxApiFailure.missingKey
        }
    }

    /// The headers the rule reads. A `Cookie` header of any kind means a browser is calling, which `SandboxApiAuth` refuses.
    static func headers(of request: Request) -> SandboxApiHeaders {
        SandboxApiHeaders(authorization: request.headers[.authorization], apiKey: request.headers[apiKeyHeader],
                          hasCookies: request.headers[.cookie] != nil)
    }

    static func badKeyKey(_ context: RootContext) -> String { "sandboxbadkey:\(context.remoteIP)" }

    // MARK: rate limits for the API's own calls

    /// A key may make this many creates per minute, per key, so one broken program cannot use up a machine's room for a whole
    /// team. The team's own hourly limit is checked by `SandboxLimits`.
    static let createsPerMinute = 30
    static let changesPerMinute = 120

    func limitCreates(for key: StoredApiKey) throws {
        guard services.throttle.allow("sandboxcreate:\(key.id)", limit: Self.createsPerMinute, seconds: 60) else {
            throw SandboxApiFailure.tooMany
        }
    }

    func limitChanges(for key: StoredApiKey) throws {
        guard services.throttle.allow("sandboxchange:\(key.id)", limit: Self.changesPerMinute, seconds: 60) else {
            throw SandboxApiFailure.tooMany
        }
    }
}
