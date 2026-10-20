import Hummingbird
import HTTPTypes
import RootCore

/// Puts the real visitor's address on the request (see ClientAddress). Only the operator listener of a public (https) panel uses it.
struct ClientAddressMiddleware: RouterMiddleware {
    static let header = HTTPField.Name(ClientAddress.header)!

    func handle(_ request: Request, context: RootContext, next: (Request, RootContext) async throws -> Response) async throws -> Response {
        var seen = context
        seen.remoteIP = ClientAddress.resolve(peer: context.remoteIP, forwarded: request.headers[Self.header], trustForwarded: true)
        return try await next(request, seen)
    }
}
