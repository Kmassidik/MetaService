import Foundation
import Hummingbird
import AgentCore

/// `GET /v1/security/events?after=<cursor>&limit=<1..2000>`: the SSH connections and the baseline of this Mac, read only. The token check (and the
/// lock-out after too many wrong tokens) is the router's TokenMiddleware.
struct SecurityRoutes {
    let service: SecurityService

    func register(on router: Router<AgentContext>) {
        router.get("/v1/security/events") { request, _ in
            let parameters = request.uri.queryParameters
            let after: [String] = parameters.getAll(SecurityQuery.afterParameter)
            let limit: [String] = parameters.getAll(SecurityQuery.limitParameter)
            let query = try SecurityQuery.parse(after: after, limit: limit)
            return try Json.response(try await service.answer(query))
        }
    }
}
