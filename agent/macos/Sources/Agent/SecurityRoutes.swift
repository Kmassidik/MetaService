import Foundation
import Hummingbird
import AgentCore
import MSCore

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
        /// `GET /v1/security/ban-status?address=X`: is X in the pf blocklist right now?
        router.get("/v1/security/ban-status") { request, _ in
            let address = request.uri.queryParameters.get("address") ?? ""
            guard !address.isEmpty else { throw InputError("address is required") }
            let banned = await service.isBanned(address)
            return try Json.response(["banned": banned])
        }
    }
}
