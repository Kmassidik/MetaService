import Foundation
import Hummingbird
import MSCore
import RootCore

/// The panel's view of the app inside one VM, and the "try again" button.
struct AppRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 120
    static let changesPerMinute = 30

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/workloads/{workload}/app", use: show)
        group.post("/api/machines/{id}/workloads/{workload}/app/retry", use: retry)
    }

    private func show(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("app-read", per: context, max: Self.readsPerMinute, seconds: 60)
        let (machine, workload) = try vm(context)
        return try Json.response(try services.apps.view(machine: machine, workload: workload))
    }

    private func retry(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("app-change", per: context, max: Self.changesPerMinute, seconds: 60)
        let (machine, workload) = try vm(context)
        return try Json.response(try services.apps.retry(actor: caller.name, machine: machine, workload: workload))
    }

    private func vm(_ context: RootContext) throws -> (machine: String, workload: String) {
        guard let machine = context.parameters.get("id"), let workload = context.parameters.get("workload"), Ids.isValid(machine), Ids.isValid(workload) else { throw ApiFailure.notFound }
        return (machine, workload)
    }
}
