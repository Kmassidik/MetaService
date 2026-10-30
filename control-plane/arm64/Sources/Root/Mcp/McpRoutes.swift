import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore
import RootStore

/// The MCP endpoint, `POST /mcp`: one JSON-RPC message per request, JSON replies only (mcp/SPEC.md section 2).
/// The checks in front, in order: the Host, the Origin of a browser, the Bearer token (401), the token's rate, the body size. GET and DELETE are 405: there is no stream and no session.
struct McpRoutes {
    let services: Services
    let guards: Guards

    static let versionHeader = HTTPField.Name("MCP-Protocol-Version")!
    static let realm = #"Bearer realm="metaservice""#

    func register(on group: RouterGroup<RootContext>) {
        group.post("/mcp", use: post)
        group.get("/mcp", use: notAllowed)
        group.delete("/mcp", use: notAllowed)
    }

    private func notAllowed(_ request: Request, context: RootContext) async throws -> Response {
        var headers = HTTPFields()
        headers[.allow] = "POST"
        headers[.contentType] = "application/json"
        let body = #"{"error":{"code":"method_not_allowed","message":"this endpoint only answers POST: there is no stream and no session"}}"#
        return Response(status: .methodNotAllowed, headers: headers, body: .init(byteBuffer: ByteBuffer(string: body)))
    }

    private func post(_ request: Request, context: RootContext) async throws -> Response {
        let mcp = services.mcp
        try guards.requireHost(request)
        guard McpProtocol.originAllowed(request.headers[.origin], publicURL: services.config.publicBaseURL) else { throw ApiFailure.forbidden("request origin not allowed") }
        guard !services.throttle.isFull(Guards.badTokenKey(context), limit: Guards.badTokenLimit) else { throw ApiFailure.tooMany }
        guard let caller = try mcp.authenticate(bearer: Guards.bearer(request), sourceIp: context.remoteIP) else { return unauthorized(context) }
        guard services.throttle.allow("mcp:\(caller.token.id)", limit: McpProtocol.requestsPerMinute, seconds: 60) else { throw ApiFailure.tooMany }
        let body = try await guards.body(request)
        switch McpJsonRpc.parse(body) {
        case .invalid(let id, let code, let message): return json(McpJsonRpc.error(id: id, code: code, message: message))
        case .notification: return Response(status: .accepted)
        case .request(let call):
            return json(await mcp.dispatch(call, caller: caller, headerVersion: request.headers[Self.versionHeader]))
        }
    }

    /// Missing, unknown, revoked and expired tokens, and a disabled person's, look the same from outside. A bad token counts toward the address's lockout.
    private func unauthorized(_ context: RootContext) -> Response {
        _ = services.throttle.allow(Guards.badTokenKey(context), limit: Guards.badTokenLimit, seconds: Guards.badTokenWindow)
        var headers = HTTPFields()
        headers[.wwwAuthenticate] = Self.realm
        headers[.contentType] = "application/json"
        let body = #"{"error":{"code":"unauthorized","message":"missing, unknown, revoked or expired token, or the person is disabled"}}"#
        return Response(status: .unauthorized, headers: headers, body: .init(byteBuffer: ByteBuffer(string: body)))
    }

    private func json(_ data: Data) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }
}
