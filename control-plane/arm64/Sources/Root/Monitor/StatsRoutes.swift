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
    /// The history is read once when a page opens, so far fewer reads are enough.
    static let historyReadsPerMinute = 30

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/stats", use: stats)
        group.get("/api/machines/{id}/stats/history", use: history)
    }

    /// The last hour of readings kept in the parent's memory, oldest first. Same guards as the live route.
    private func history(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("machine-stats-history", per: context, max: Self.historyReadsPerMinute, seconds: 60)
        let id = try context.machineId()
        let points = try wantsPoints(request)
        do {
            return try Json.response(try await services.history.reply(for: id, points: points))
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
    }

    private func wantsPoints(_ request: Request) throws -> Int {
        do {
            return try HistoryQuery.points(values: request.uri.queryParameters.getAll(HistoryQuery.parameter))
        } catch let refused as HistoryQuery.Refused {
            throw ApiFailure.invalid(refused.message)
        }
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
