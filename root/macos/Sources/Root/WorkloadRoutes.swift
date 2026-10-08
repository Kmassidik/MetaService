import Foundation
import Hummingbird
import RootCore
import RootStore

/// Operators asking machines to create, start, stop or delete workloads, and reading how those requests went.
struct WorkloadRoutes {
    let services: Services
    let guards: Guards

    static let createsPerMinute = 20
    static let actionsPerMinute = 60

    func register(on group: RouterGroup<RootContext>) {
        group.post("/api/workloads", use: create)
        group.post("/api/machines/{id}/workloads/{workload}/start") { request, context in try await self.act(request, context, .start) }
        group.post("/api/machines/{id}/workloads/{workload}/stop") { request, context in try await self.act(request, context, .stop) }
        group.post("/api/machines/{id}/workloads/{workload}/delete") { request, context in try await self.act(request, context, .delete) }
        group.get("/api/commands", use: list)
        group.get("/api/commands/{id}", use: show)
    }

    private func create(_ request: Request, context: RootContext) async throws -> Response {
        let session = try guards.operatorWrite(request)
        try guards.limit("workload-create", per: context, max: Self.createsPerMinute, seconds: 60)
        let wish = try CreateWorkloadOperatorRequest(body: try await guards.body(request))
        return try Json.response(Reply(command: try await services.workloads.create(actor: session.email, request: wish)), status: .accepted)
    }

    private func act(_ request: Request, _ context: RootContext, _ action: WorkloadService.Action) async throws -> Response {
        let session = try guards.operatorWrite(request)
        try guards.limit("workload-act", per: context, max: Self.actionsPerMinute, seconds: 60)
        if action == .delete { _ = try ConfirmRequest(body: try await guards.body(request)) }
        guard let machine = context.parameters.get("id"), let workload = context.parameters.get("workload"), Ids.isValid(machine), Ids.isValid(workload) else { throw ApiFailure.notFound }
        let command = try await services.workloads.act(actor: session.email, machine: machine, workload: workload, action: action)
        return try Json.response(Reply(command: command), status: .accepted)
    }

    private func list(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorSession(request)
        let limit = request.uri.queryParameters.get("limit", as: Int.self) ?? 30
        return try Json.response(Commands(commands: try services.commands.recent(limit: limit)))
    }

    private func show(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorSession(request)
        guard let id = context.parameters.get("id"), Ids.isValid(id), let command = try services.commands.get(id) else { throw ApiFailure.notFound }
        return try Json.response(Reply(command: command))
    }
}

private struct Reply: Encodable { let command: CommandRow }
private struct Commands: Encodable { let commands: [CommandRow] }
