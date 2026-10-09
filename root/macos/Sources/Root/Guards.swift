import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore
import RootStore

struct OperatorCaller {
    let name: String
}

/// The checks that sit in front of routes: who is calling, may they write, how big is the body.
struct Guards {
    let services: Services

    static let badTokenLimit = 10
    static let badTokenWindow: TimeInterval = 60
    static let csrfHeader = HTTPField.Name("X-CSRF-Token")!

    // MARK: operators

    /// The one operator. There is no sign-in: the listener is only reachable from this machine, and access from outside is a proxy's job.
    static let operatorName = "operator"

    /// For anything the panel reads: the request must be addressed to this machine's own name, which stops DNS rebinding.
    func operatorRead(_ request: Request) throws -> OperatorCaller {
        guard OperatorGate.hostMatches(header: request.head.authority, publicURL: services.config.publicBaseURL) else {
            throw ApiFailure.forbidden("request host not allowed")
        }
        return OperatorCaller(name: Self.operatorName)
    }

    /// For anything that changes state: the same host check, plus the exact Origin and the CSRF header, which another site cannot send.
    func operatorWrite(_ request: Request) throws -> OperatorCaller {
        let caller = try operatorRead(request)
        guard Origin.matches(header: request.headers[.origin], expected: services.config.publicBaseURL) else {
            throw ApiFailure.forbidden("request origin not allowed")
        }
        guard let sent = request.headers[Self.csrfHeader], Tokens.constantTimeEqual(sent, services.csrfToken) else {
            throw ApiFailure.forbidden("missing or wrong CSRF token")
        }
        return caller
    }

    // MARK: machines

    /// The machine id behind the Bearer token. Too many bad tokens from one address locks that address out for a minute.
    func machine(_ request: Request, context: RootContext) throws -> String {
        let token = try bearerOrRefuse(request, context: context)
        guard let id = try services.machines.authenticate(tokenHash: Tokens.sha256Hex(token)) else {
            _ = services.throttle.allow(Self.badTokenKey(context), limit: Self.badTokenLimit, seconds: Self.badTokenWindow)
            throw ApiFailure.unauthorized("missing or wrong token")
        }
        return id
    }

    /// The Bearer token of a request, after checking this address is not locked out for sending too many bad ones.
    func bearerOrRefuse(_ request: Request, context: RootContext) throws -> String {
        guard !services.throttle.isFull(Self.badTokenKey(context), limit: Self.badTokenLimit) else { throw ApiFailure.tooMany }
        guard let token = Self.bearer(request) else {
            _ = services.throttle.allow(Self.badTokenKey(context), limit: Self.badTokenLimit, seconds: Self.badTokenWindow)
            throw ApiFailure.unauthorized("missing or wrong token")
        }
        return token
    }

    static func badTokenKey(_ context: RootContext) -> String { "badtoken:\(context.remoteIP)" }

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
