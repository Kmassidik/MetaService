import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// The network usage of the machines: totals for today, this month or 30 days, and a per-day series. A read: the operator's session and the right Host, like the stats routes.
struct NetUsageRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 30
    static let limitWindowSeconds: TimeInterval = 60

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/network/usage", use: usage)
        group.get("/api/network/usage/daily", use: daily)
    }

    private func usage(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("network-usage", per: context, max: Self.readsPerMinute, seconds: Self.limitWindowSeconds)
        let range = try wantsRange(request)
        return try Json.response(try services.netUsage.usageReply(range: range))
    }

    private func daily(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("network-usage-daily", per: context, max: Self.readsPerMinute, seconds: Self.limitWindowSeconds)
        let days = try wantsDays(request)
        return try Json.response(try services.netUsage.dailyReply(days: days))
    }

    /// `?range=today` (or nothing), `month` or `30d`. Anything else is a 400.
    private func wantsRange(_ request: Request) throws -> NetUsageRange {
        do {
            return try NetUsageRange.parse(values: request.uri.queryParameters.getAll(NetUsageRange.parameter))
        } catch let refused as NetUsageRange.Refused {
            throw ApiFailure.invalid(refused.message)
        }
    }

    /// `?days=7` (or nothing) or `30`. Anything else is a 400.
    private func wantsDays(_ request: Request) throws -> NetUsageDays {
        do {
            return try NetUsageDays.parse(values: request.uri.queryParameters.getAll(NetUsageDays.parameter))
        } catch let refused as NetUsageDays.Refused {
            throw ApiFailure.invalid(refused.message)
        }
    }
}
