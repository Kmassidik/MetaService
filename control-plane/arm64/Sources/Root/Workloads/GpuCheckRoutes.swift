import Foundation
import Hummingbird
import RootCore

/// The panel's "Check the GPU" button. A look inside, nothing changes, so a read (the session and the right Host) is enough for GET; POST is the same with the write checks (Origin and CSRF).
/// Both are limited per person, and per workload in the service.
struct GpuCheckRoutes {
    let services: Services
    let guards: Guards

    static let checksPerMinute = 30

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/workloads/{workload}/gpu-check") { request, context in
            _ = try guards.operatorRead(request)
            return try await check(context)
        }
        group.post("/api/machines/{id}/workloads/{workload}/gpu-check") { request, context in
            _ = try guards.operatorWrite(request)
            return try await check(context)
        }
    }

    private func check(_ context: RootContext) async throws -> Response {
        try guards.limit("gpu-check", per: context, max: Self.checksPerMinute, seconds: 60)
        guard let machine = context.parameters.get("id"), let workload = context.parameters.get("workload"), Ids.isValid(machine), Ids.isValid(workload) else { throw ApiFailure.notFound }
        return try Json.response(try await services.gpuCheck.check(machine: machine, workload: workload))
    }
}
