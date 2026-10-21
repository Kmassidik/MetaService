import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// What the panel reads to show a machine's real state. A read: the operator's session and the right Host, like the other reads.
struct StatsRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 120

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/stats", use: stats)
    }

    private func stats(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("machine-stats", per: context, max: Self.readsPerMinute, seconds: 60)
        let id = try context.machineId()
        let processes = try wantsProcesses(request)
        do {
            return try Json.response(try await services.stats.reply(for: id, processes: processes))
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
    }

    /// `?processes=1` (or nothing) keeps the top programs in the answer, `?processes=0` leaves them out. Anything else is a 400.
    private func wantsProcesses(_ request: Request) throws -> Bool {
        do {
            return try StatsQuery.wantsProcesses(values: request.uri.queryParameters.getAll(StatsQuery.parameter))
        } catch let refused as StatsQuery.Refused {
            throw ApiFailure.invalid(refused.message)
        }
    }
}
