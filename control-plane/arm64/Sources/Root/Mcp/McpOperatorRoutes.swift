import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore
import RootStore

/// What the panel's AI access section calls (mcp/SPEC.md section 7): the same session, Origin and CSRF rules as every operator route.
/// The token text leaves the parent once, in the answer that made it.
struct McpOperatorRoutes {
    let services: Services
    let guards: Guards

    static let defaultActivityPage = 20
    static let tokenCreatesPerMinute = 20
    static let recentApprovals = 30

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/mcp/info", use: info)
        group.get("/api/mcp/tokens", use: listTokens)
        group.post("/api/mcp/tokens", use: createToken)
        group.delete("/api/mcp/tokens/{id}", use: revokeToken)
        group.get("/api/mcp/approvals", use: approvals)
        group.post("/api/mcp/approvals/{id}/approve", use: approve)
        group.post("/api/mcp/approvals/{id}/deny", use: deny)
        group.get("/api/mcp/activity", use: activity)
    }

    private var mcp: McpService { services.mcp }

    private func reply(_ object: [String: Any], status: HTTPResponse.Status = .ok) throws -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }

    private func info(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        return try reply(mcp.infoView())
    }

    private func listTokens(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        return try reply(["tokens": try mcp.tokens.list().map(mcp.tokenView)])
    }

    private func createToken(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("mcp-token-create", per: context, max: Self.tokenCreatesPerMinute, seconds: 60)
        let wish = try McpTokenRequest(body: try await guards.body(request))
        guard try !mcp.tokens.liveNameExists(wish.name) else { throw ApiFailure(status: .conflict, code: "name_taken", message: "a token with that name already exists: revoke it first or choose another name") }
        let text = McpToken.make()
        let now = services.clock.now
        let made = NewMcpToken(id: McpService.newId("mt-"), name: wish.name, prefix: McpToken.displayPrefix(of: text), tokenHash: McpToken.hash(text), scopes: wish.scopes, quotas: wish.quotas,
                               autoApprove: wish.autoApprove, createdBy: caller.name, createdAt: now, expiresAt: now.addingTimeInterval(TimeInterval(wish.expiresInDays) * 86_400))
        try mcp.tokens.create(made)
        try services.audit.record(actor: caller.name, action: "mcp.token_create", target: made.name, detail: ["prefix": made.prefix, "scopes": McpScope.names(made.scopes).joined(separator: ",")], at: now)
        guard let stored = try mcp.tokens.get(id: made.id) else { throw ApiFailure(status: .internalServerError, code: "internal", message: "internal error") }
        return try reply(["token": text, "info": mcp.tokenView(stored)], status: .created)
    }

    private func revokeToken(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        let id = try context.machineId()
        guard let token = try mcp.tokens.get(id: id) else { throw ApiFailure.notFound }
        if try mcp.tokens.revoke(id: id, now: services.clock.now) {
            try services.audit.record(actor: caller.name, action: "mcp.token_revoke", target: token.name, detail: ["prefix": token.prefix], at: services.clock.now)
        }
        guard let revoked = try mcp.tokens.get(id: id) else { throw ApiFailure.notFound }
        return try reply(["info": mcp.tokenView(revoked)])
    }

    private func approvals(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        _ = try mcp.requests.expireOld(now: services.clock.now)
        return try reply(["pending": try mcp.requests.pending().map(mcp.approvalView), "recent": try mcp.requests.recent(limit: Self.recentApprovals).map(mcp.approvalView)])
    }

    private func approve(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        let decided = try await mcp.approve(try context.machineId(), operatorName: caller.name)
        return try reply(["approval": mcp.approvalView(decided)])
    }

    private func deny(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        return try reply(["approval": mcp.approvalView(try mcp.deny(try context.machineId(), operatorName: caller.name))])
    }

    private func activity(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        let limit = request.uri.queryParameters.get("limit", as: Int.self) ?? Self.defaultActivityPage
        return try reply(["activity": try mcp.activity.recent(limit: limit).map(mcp.activityView)])
    }
}
