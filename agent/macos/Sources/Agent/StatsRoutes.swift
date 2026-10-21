import Hummingbird
import AgentCore

/// `GET /v1/stats`: the machine's real numbers now, read only (docs/monitor-contract.md). The token check is the router's TokenMiddleware.
struct StatsRoutes {
    let sampler: StatsSampler

    func register(on router: Router<AgentContext>) {
        router.get("/v1/stats") { _, _ in
            let stats = try sampler.sample()
            return Json.raw(try StatsJson.encode(stats))
        }
    }
}
