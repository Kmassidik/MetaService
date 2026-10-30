import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore
import RootStore

/// What the panel's AI access section calls (mcp/SPEC.md sections 7 and 10): the same session, Origin and CSRF rules as every operator route.
/// The token text leaves the parent once, in the answer that made it.
struct McpOperatorRoutes {
    let services: Services
    let guards: Guards

    static let defaultActivityPage = 20
    static let writesPerMinute = 20

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/mcp/info", use: info)
        group.get("/api/mcp/people", use: listPeople)
        group.post("/api/mcp/people", use: addPerson)
        group.patch("/api/mcp/people/{id}", use: changePerson)
        group.post("/api/mcp/people/{id}/disable") { request, context in try await self.setDisabled(request, context, true) }
        group.post("/api/mcp/people/{id}/enable") { request, context in try await self.setDisabled(request, context, false) }
        group.get("/api/mcp/tokens", use: listTokens)
        group.post("/api/mcp/tokens", use: createToken)
        group.delete("/api/mcp/tokens/{id}", use: revokeToken)
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

    // MARK: people

    private func listPeople(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        return try reply(["people": try mcp.people.list().map(mcp.personView)])
    }

    private func addPerson(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("mcp-write", per: context, max: Self.writesPerMinute, seconds: 60)
        let wish = try McpPersonRequest.creating(body: try await guards.body(request))
        guard let name = wish.name, let scopes = wish.scopes, let quotas = wish.quotas else { throw ApiFailure.invalid("name is required") }
        let id = McpService.newId("mp-")
        do {
            try mcp.people.create(id: id, name: name, scopes: scopes, quotas: quotas, now: services.clock.now)
        } catch McpPeopleError.nameTaken {
            throw ApiFailure(status: .conflict, code: "name_taken", message: "a person with that name already exists")
        }
        try services.audit.record(actor: caller.name, action: "mcp.person_add", target: name, detail: ["scopes": McpScope.names(scopes).joined(separator: ",")], at: services.clock.now)
        return try reply(["person": try personView(id)], status: .created)
    }

    private func changePerson(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        let id = try context.machineId()
        let change = try McpPersonRequest.changing(body: try await guards.body(request))
        let person = try existing(id)
        try mcp.people.change(id: id, scopes: change.scopes, quotas: change.quotas)
        try services.audit.record(actor: caller.name, action: "mcp.person_change", target: person.name, at: services.clock.now)
        return try reply(["person": try personView(id)])
    }

    private func setDisabled(_ request: Request, _ context: RootContext, _ disabled: Bool) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        let id = try context.machineId()
        let person = try existing(id)
        if try mcp.people.setDisabled(id: id, disabled, now: services.clock.now) {
            try services.audit.record(actor: caller.name, action: disabled ? "mcp.person_disable" : "mcp.person_enable", target: person.name, at: services.clock.now)
        }
        return try reply(["person": try personView(id)])
    }

    private func existing(_ id: String) throws -> McpPersonRecord {
        guard let person = try mcp.people.get(id: id) else { throw ApiFailure.notFound }
        return person
    }

    private func personView(_ id: String) throws -> [String: Any] { mcp.personView(try existing(id)) }

    // MARK: tokens

    private func listTokens(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        return try reply(["tokens": try mcp.tokens.list().map(mcp.tokenView)])
    }

    private func createToken(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("mcp-write", per: context, max: Self.writesPerMinute, seconds: 60)
        let wish = try McpTokenRequest(body: try await guards.body(request))
        let person = try existing(wish.personId)
        guard !person.isDisabled else { throw ApiFailure(status: .conflict, code: "person_disabled", message: "this person is disabled: enable them first") }
        let scopes = wish.scopes ?? person.scopes
        guard scopes.isSubset(of: person.scopes) else { throw ApiFailure.invalid("the token's scopes must be among \(person.name)'s: \(McpScope.names(person.scopes).joined(separator: ", "))") }
        let text = McpToken.make()
        let now = services.clock.now
        let made = NewMcpToken(id: McpService.newId("mt-"), name: wish.name, prefix: McpToken.displayPrefix(of: text), personId: person.id, tokenHash: McpToken.hash(text), scopes: scopes,
                               createdBy: caller.name, createdAt: now, expiresAt: now.addingTimeInterval(TimeInterval(wish.expiresInDays) * 86_400))
        try mcp.tokens.create(made)
        try services.audit.record(actor: caller.name, action: "mcp.token_create", target: person.name, detail: ["token": made.name, "prefix": made.prefix, "scopes": McpScope.names(scopes).joined(separator: ",")], at: now)
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

    private func activity(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        let limit = request.uri.queryParameters.get("limit", as: Int.self) ?? Self.defaultActivityPage
        return try reply(["activity": try mcp.activity.recent(limit: limit).map(mcp.activityView)])
    }
}
