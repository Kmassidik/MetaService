import Foundation
import Hummingbird
import RootCore
import RootStore

/// Operator routes for unowned Docker, Incus and Apple services. No delete route exists.
struct ExternalServiceRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 120
    static let actionsPerMinute = 60

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/external-services", use: list)
        group.post("/api/machines/{id}/external-services/{service}/start") { request, context in
            try await self.act(request, context, .start)
        }
        group.post("/api/machines/{id}/external-services/{service}/stop") { request, context in
            try await self.act(request, context, .stop)
        }
        group.post("/api/machines/{id}/external-services/{service}/restart") { request, context in
            try await self.act(request, context, .restart)
        }
    }

    private func list(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("external-services-read", per: context, max: Self.readsPerMinute, seconds: 60)
        let id = try context.machineId()
        return try Json.response(try await services.externalServices.list(machine: id))
    }

    private func act(_ request: Request, _ context: RootContext, _ action: ExternalServicesService.Action) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("external-service-act", per: context, max: Self.actionsPerMinute, seconds: 60)
        let machine = try context.machineId()
        guard let rawId = context.parameters.get("service"), let externalId = rawId.removingPercentEncoding else { throw ApiFailure.notFound }
        let command = try await services.externalServices.act(actor: caller.name, machine: machine, externalId: externalId, action: action)
        return try Json.response(Reply(command: command), status: .accepted)
    }
}

private struct Reply: Encodable { let command: CommandRow }
