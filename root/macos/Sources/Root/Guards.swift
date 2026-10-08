import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore
import RootStore

/// The checks that sit in front of routes: who is calling, may they write, how big is the body.
struct Guards {
    let services: Services

    static let badTokenLimit = 10
    static let badTokenWindow: TimeInterval = 60
    static let csrfHeader = HTTPField.Name("X-CSRF-Token")!

    // MARK: operators

    func operatorSession(_ request: Request) throws -> SessionRecord {
        let cookie = Cookies.value(named: services.config.sessionCookieName, header: request.headers[.cookie])
        guard let cookie, let session = try services.sessions.lookup(token: cookie, now: services.clock.now) else { throw ApiFailure.unauthorized() }
        return session
    }

    /// For anything that changes state: a valid session, the CSRF token, and the exact Origin.
    func operatorWrite(_ request: Request) throws -> SessionRecord {
        let session = try operatorSession(request)
        guard Origin.matches(header: request.headers[.origin], expected: services.config.publicBaseURL) else {
            throw ApiFailure.forbidden("request origin not allowed")
        }
        guard let sent = request.headers[Self.csrfHeader], Tokens.constantTimeEqual(sent, session.csrfToken) else {
            throw ApiFailure.forbidden("missing or wrong CSRF token")
        }
        return session
    }

    // MARK: machines

    /// The machine id behind the Bearer token. Too many bad tokens from one address locks that address out for a minute.
    func machine(_ request: Request, context: RootContext) throws -> String {
        let lockKey = "badtoken:\(context.remoteIP)"
        guard !services.throttle.isFull(lockKey, limit: Self.badTokenLimit) else { throw ApiFailure.tooMany }
        guard let token = Self.bearer(request), let id = try services.machines.authenticate(tokenHash: Tokens.sha256Hex(token)) else {
            _ = services.throttle.allow(lockKey, limit: Self.badTokenLimit, seconds: Self.badTokenWindow)
            throw ApiFailure.unauthorized("missing or wrong token")
        }
        return id
    }

    static func bearer(_ request: Request) -> String? {
        guard let header = request.headers[.authorization], header.hasPrefix("Bearer "), header.count <= 600 else { return nil }
        let token = String(header.dropFirst("Bearer ".count))
        return token.isEmpty ? nil : token
    }

    // MARK: bodies and rate limits

    func body(_ request: Request) async throws -> Data {
        if let declared = request.headers[.contentLength].flatMap({ Int($0) }), declared > RootContext.maxBodyBytes {
            throw HTTPError(.contentTooLarge)
        }
        let buffer = try await request.body.collect(upTo: RootContext.maxBodyBytes)
        return Data(buffer.readableBytesView)
    }

    func limit(_ name: String, per context: RootContext, max: Int, seconds: TimeInterval) throws {
        guard services.throttle.allow("\(name):\(context.remoteIP)", limit: max, seconds: seconds) else { throw ApiFailure.tooMany }
    }
}
