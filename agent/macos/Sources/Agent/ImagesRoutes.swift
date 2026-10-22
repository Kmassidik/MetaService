import Hummingbird
import AgentCore

/// `GET /v1/images`: the ready-made images this machine has prepared (read only). The token check is the router's TokenMiddleware.
struct ImagesRoutes {
    func register(on router: Router<AgentContext>) {
        router.get("/v1/images") { _, _ in Json.raw(PreparedImages.stockOnly) }
    }
}
