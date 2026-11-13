import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// The network speed of a machine over time, from the stored minutes. A read: the operator's session and the right Host, like the latency route.
struct NetSeriesRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 30
    static let limitWindowSeconds: TimeInterval = 60

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/network/series", use: series)
    }

    private func series(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("machine-network-series", per: context, max: Self.readsPerMinute, seconds: Self.limitWindowSeconds)
        let id = try context.machineId()
        let range = try wantsRange(request)
        do {
            return try Json.response(try services.netUsage.seriesReply(machineId: id, range: range))
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
    }

    /// `?range=24h` (or nothing), `7d` or `30d`. Anything else is a 400.
    private func wantsRange(_ request: Request) throws -> NetSeriesRange {
        guard let range = NetSeriesRange.parse(request.uri.queryParameters.get(NetSeriesRange.parameter)) else {
            throw ApiFailure.invalid(NetSeriesRange.refusalMessage)
        }
        return range
    }
}
