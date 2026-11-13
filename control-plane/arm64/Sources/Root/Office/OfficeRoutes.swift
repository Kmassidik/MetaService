import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// The office bandwidth of the WAN interfaces: totals for today, this month or 30 days, a per-day series and the interface names. A read: the operator's session and the right Host, like the network usage routes.
struct OfficeRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 30
    static let limitWindowSeconds: TimeInterval = 60

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/office/bandwidth", use: usage)
        group.get("/api/office/bandwidth/daily", use: daily)
        group.get("/api/office/bandwidth/interfaces", use: interfaces)
    }

    private func usage(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("office-bandwidth", per: context, max: Self.readsPerMinute, seconds: Self.limitWindowSeconds)
        let range = try wantsRange(request)
        return try Json.response(try await services.officeBandwidth.usageReply(range: range))
    }

    private func daily(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("office-bandwidth-daily", per: context, max: Self.readsPerMinute, seconds: Self.limitWindowSeconds)
        let days = try wantsDays(request)
        return try Json.response(try services.officeBandwidth.dailyReply(days: days))
    }

    /// A live walk of the router. When the router cannot be read, the answer is a fixed 503 with the poller's fixed text; the router's own error is never sent.
    private func interfaces(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("office-bandwidth-interfaces", per: context, max: Self.readsPerMinute, seconds: Self.limitWindowSeconds)
        do {
            return try Json.response(try await services.officeBandwidth.interfacesReply())
        } catch {
            throw ApiFailure(status: .serviceUnavailable, code: "router_unavailable", message: OfficeFailure.phrase(for: error))
        }
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
