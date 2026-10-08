import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore

/// An expected refusal. Becomes {"error": {"code", "message"}} with the given status.
struct ApiFailure: Error {
    let status: HTTPResponse.Status
    let code: String
    let message: String

    static func unauthorized(_ message: String = "sign in required") -> ApiFailure { .init(status: .unauthorized, code: "unauthorized", message: message) }
    static func forbidden(_ message: String) -> ApiFailure { .init(status: .forbidden, code: "forbidden", message: message) }
    static func invalid(_ message: String) -> ApiFailure { .init(status: .badRequest, code: "invalid_input", message: message) }
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
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(data: try encoder.encode(value))))
    }

    /// A refusal that carries the numbers behind it, in the contract's shape.
    static func refusal(_ refusal: PlacementRefusal) -> Response {
        let status: HTTPResponse.Status = refusal.code == "machine_not_found" ? .notFound : .conflict
        let body: [String: Any] = ["error": ["code": refusal.code, "message": refusal.message, "resource": refusal.resource, "needed": refusal.needed, "free": refusal.free]]
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }

    static func failure(_ failure: ApiFailure) -> Response {
        let body = ["error": ["code": failure.code, "message": failure.message]]
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return Response(status: failure.status, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }
}

/// Turns every error into the contract's error shape. Unknown errors say nothing about the inside.
struct ErrorMiddleware: RouterMiddleware {
    func handle(_ request: Request, context: RootContext, next: (Request, RootContext) async throws -> Response) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let failure as ApiFailure {
            return Json.failure(failure)
        } catch let refusal as PlacementRefusal {
            return Json.refusal(refusal)
        } catch let error as InputError {
            return Json.failure(.invalid(error.message))
        } catch let error as HTTPError {
            return Json.failure(ApiFailure(status: error.status, code: Self.code(for: error.status), message: "request refused"))
        } catch {
            context.logger.error("unexpected error: \(type(of: error))")
            return Json.failure(ApiFailure(status: .internalServerError, code: "internal", message: "internal error"))
        }
    }

    private static func code(for status: HTTPResponse.Status) -> String {
        switch status {
        case .contentTooLarge: return "too_large"
        case .notFound: return "not_found"
        case .methodNotAllowed: return "not_found"
        default: return "refused"
        }
    }
}
