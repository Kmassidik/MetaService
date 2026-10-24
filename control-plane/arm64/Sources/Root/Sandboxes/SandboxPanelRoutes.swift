import Foundation
import Hummingbird
import HTTPTypes
import MSCore
import RootCore

/// The panel's sandbox pages: API keys, the live list, an operator's kill and pause, and the usage table. Every route sits
/// behind the same operator guards as the rest of the panel: the request's Host, the session cookie, and for a change the
/// exact Origin and the session's CSRF header. None of it is reachable with an API key.
struct SandboxPanelRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 240
    static let changesPerMinute = 60
    /// The form's field is bounded a little above the rule's own limit, so too long a name gets the rule's plain words.
    static let pastedNameCharacters = SandboxTeamRules.nameMax * 2

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/sandboxes/keys", use: listKeys)
        group.post("/api/sandboxes/keys", use: createKey)
        group.delete("/api/sandboxes/keys/{keyID}", use: revokeKey)
        group.get("/api/sandboxes/usage", use: usage)
        group.get("/api/sandboxes", use: list)
        group.post("/api/sandboxes/{sandboxID}/kill", use: kill)
        group.post("/api/sandboxes/{sandboxID}/pause", use: pause)
    }

    private var service: SandboxPanelService { SandboxPanelService(services: services, helper: services.sandboxHelper) }

    // MARK: keys

    private func listKeys(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("sandbox-panel-read", per: context, max: Self.readsPerMinute, seconds: 60)
        return try Json.response(try service.keys())
    }

    /// Makes a key and answers with its text. This is the only answer that ever carries the key.
    private func createKey(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("sandbox-panel-change", per: context, max: Self.changesPerMinute, seconds: 60)
        let body = try NewKeyBody(data: try await guards.body(request))
        let made = try service.makeKey(teamName: body.teamName, actor: SandboxPanelService.actor(caller.name))
        return try Json.response(made, status: .created)
    }

    private func revokeKey(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("sandbox-panel-change", per: context, max: Self.changesPerMinute, seconds: 60)
        guard let id = context.parameters.get("keyID"), Ids.isValid(id) else { throw ApiFailure.notFound }
        try service.revokeKey(id: id, actor: SandboxPanelService.actor(caller.name))
        return Response(status: .noContent)
    }

    // MARK: sandboxes

    private func list(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("sandbox-panel-read", per: context, max: Self.readsPerMinute, seconds: 60)
        return try Json.response(try service.sandboxes())
    }

    private func kill(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("sandbox-panel-change", per: context, max: Self.changesPerMinute, seconds: 60)
        try await service.kill(id: try sandboxID(context), actor: SandboxPanelService.actor(caller.name))
        return Response(status: .noContent)
    }

    private func pause(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("sandbox-panel-change", per: context, max: Self.changesPerMinute, seconds: 60)
        try await service.pause(id: try sandboxID(context), actor: SandboxPanelService.actor(caller.name))
        return Response(status: .noContent)
    }

    // MARK: usage

    /// The window's totals per team. `?days=` is whole days from 1 to 90; absent or unreadable is the default of 7.
    private func usage(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("sandbox-panel-read", per: context, max: Self.readsPerMinute, seconds: 60)
        let days = request.uri.queryParameters.get("days", as: Int.self)
        return try Json.response(try service.usage(days: days))
    }

    // MARK: pieces

    /// A sandbox id that is not even shaped like one is "no such sandbox", the same as an unknown one.
    private func sandboxID(_ context: RootContext) throws -> String {
        guard let id = context.parameters.get("sandboxID"), SandboxIdentity.isValid(id) else { throw ApiFailure.notFound }
        return id
    }

    /// The create form's body: a team name, or nothing at all (the default team). An empty body is the same as none.
    private struct NewKeyBody {
        let teamName: String?

        init(data: Data) throws {
            guard !data.isEmpty else {
                teamName = nil
                return
            }
            let object = try StrictObject(data: data, allowed: ["team_name"])
            teamName = try object.optionalString("team_name", maxLength: SandboxPanelRoutes.pastedNameCharacters)
        }
    }
}
