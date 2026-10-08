import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import AgentCore
import MSCore

struct AgentContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    let remoteIP: String

    static let maxBodyBytes = 64 * 1024
    var maxUploadSize: Int { Self.maxBodyBytes }

    init(source: ApplicationRequestContextSource) {
        coreContext = .init(source: source)
        remoteIP = source.channel.remoteAddress?.ipAddress ?? "unknown"
    }
}

struct ApiFailure: Error {
    let status: HTTPResponse.Status
    let code: String
    let message: String

    static let unauthorized = ApiFailure(status: .unauthorized, code: "unauthorized", message: "missing or wrong token")
    static let notFound = ApiFailure(status: .notFound, code: "not_found", message: "no such thing")
    static let tooMany = ApiFailure(status: .tooManyRequests, code: "rate_limited", message: "too many requests, try again shortly")
}

enum Json {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static func response<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
        make(try encoder.encode(value), status)
    }

    static func error(_ status: HTTPResponse.Status, _ code: String, _ message: String, extra: [String: Any] = [:]) -> Response {
        let body = ["error": ["code": code, "message": message].merging(extra) { $1 }]
        return make((try? JSONSerialization.data(withJSONObject: body)) ?? Data(), status)
    }

    private static func make(_ data: Data, _ status: HTTPResponse.Status) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }
}

/// Headers on every reply, errors included, so it wraps everything else.
struct SecurityHeadersMiddleware: RouterMiddleware {
    func handle(_ request: Request, context: AgentContext, next: (Request, AgentContext) async throws -> Response) async throws -> Response {
        var response = try await next(request, context)
        response.headers[.cacheControl] = "no-store"
        response.headers[HTTPField.Name("X-Content-Type-Options")!] = "nosniff"
        response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
        response.headers[HTTPField.Name("Content-Security-Policy")!] = "default-src 'none'; frame-ancestors 'none'"
        response.headers[HTTPField.Name("X-MetaService-Contract")!] = Contract.version
        return response
    }
}

/// Turns every error into the contract's error shape. Unknown errors say nothing about the inside.
struct ErrorMiddleware: RouterMiddleware {
    func handle(_ request: Request, context: AgentContext, next: (Request, AgentContext) async throws -> Response) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let failure as ApiFailure {
            return Json.error(failure.status, failure.code, failure.message)
        } catch let error as InputError {
            return Json.error(.badRequest, "invalid_input", error.message)
        } catch let refusal as Refusal {
            return Json.error(.conflict, refusal.code.rawValue, refusal.message, extra: ["resource": refusal.resource.rawValue, "needed": refusal.needed, "free": refusal.free])
        } catch AgentError.notFound {
            return Json.error(.notFound, "not_found", "no such thing")
        } catch let error as HTTPError {
            return Json.error(error.status, error.status == .contentTooLarge ? "too_large" : "refused", "request refused")
        } catch {
            context.logger.error("unexpected error: \(type(of: error))")
            return Json.error(.internalServerError, "internal", "internal error")
        }
    }
}

/// Every request needs the machine token. Too many wrong ones from one address lock that address out for a minute.
struct TokenMiddleware: RouterMiddleware {
    let token: String
    var badLimit = 10
    let throttle = Throttle()

    static let badWindow: TimeInterval = 60

    func handle(_ request: Request, context: AgentContext, next: (Request, AgentContext) async throws -> Response) async throws -> Response {
        let key = "badtoken:\(context.remoteIP)"
        guard !throttle.isFull(key, limit: badLimit) else { throw ApiFailure.tooMany }
        guard let sent = Self.bearer(request), Tokens.constantTimeEqual(sent, token) else {
            _ = throttle.allow(key, limit: badLimit, seconds: Self.badWindow)
            throw ApiFailure.unauthorized
        }
        return try await next(request, context)
    }

    static func bearer(_ request: Request) -> String? {
        guard let header = request.headers[.authorization], header.hasPrefix("Bearer "), header.count <= 600 else { return nil }
        return String(header.dropFirst("Bearer ".count))
    }
}
