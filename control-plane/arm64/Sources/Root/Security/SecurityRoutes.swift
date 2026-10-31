import Foundation
import Hummingbird
import RootCore

/// What the Security page reads. Reads only: the operator's session and the right Host, like the other reads.
struct SecurityRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 120

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/security/overview", use: overview)
        group.get("/api/security/events", use: events)
    }

    private func overview(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("security-overview", per: context, max: Self.readsPerMinute, seconds: 60)
        let range = try refusing { try SecurityQuery.overview(pairs(request)) }
        return try Json.response(try services.security.overview(range: range))
    }

    private func events(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("security-events", per: context, max: Self.readsPerMinute, seconds: 60)
        let query = try refusing { try SecurityQuery.events(pairs(request)) }
        return try Json.response(try services.security.events(query))
    }

    private func pairs(_ request: Request) -> [(String, String)] {
        request.uri.queryParameters.map { (String($0.key), String($0.value)) }
    }

    private func refusing<T>(_ read: () throws -> T) throws -> T {
        do {
            return try read()
        } catch let refused as SecurityQuery.Refused {
            throw ApiFailure.invalid(refused.message)
        }
    }
}
