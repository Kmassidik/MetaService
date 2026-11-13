import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// The latency of a machine to its helper port. A read: the operator's session and the right Host, like the stats routes.
struct LatencyRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 30

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/latency", use: latency)
    }

    private func latency(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("machine-latency", per: context, max: Self.readsPerMinute, seconds: 60)
        let id = try context.machineId()
        let range = try wantsRange(request)
        do {
            return try Json.response(try services.latency.reply(for: id, range: range))
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
    }

    /// `?range=1h` (or nothing) is the last hour, `24h` and `7d` the longer ones. Anything else is a 400.
    private func wantsRange(_ request: Request) throws -> LatencyRange {
        do {
            return try LatencyRange.parse(values: request.uri.queryParameters.getAll(LatencyRange.parameter))
        } catch let refused as LatencyRange.Refused {
            throw ApiFailure.invalid(refused.message)
        }
    }
}
