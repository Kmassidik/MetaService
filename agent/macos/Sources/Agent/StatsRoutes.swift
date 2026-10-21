import Hummingbird
import AgentCore

/// `GET /v1/stats` (optional `?processes=0` skips the program scan): the machine's real numbers now, read only (docs/monitor-contract.md). The token check is the router's TokenMiddleware.
struct StatsRoutes {
    let sampler: StatsSampler

    func register(on router: Router<AgentContext>) {
        router.get("/v1/stats") { request, _ in
            let includeProcesses = try StatsRequest.includesProcesses(values: request.uri.queryParameters.getAll(StatsRequest.parameter))
            let stats = try sampler.sample(includeProcesses: includeProcesses)
            return Json.raw(try StatsJson.encode(stats))
        }
    }
}
