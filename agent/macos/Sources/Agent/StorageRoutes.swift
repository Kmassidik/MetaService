import Hummingbird
import AgentCore

/// GET never starts work; POST starts/coalesces a background root scan and always answers immediately.
struct StorageRoutes {
    let state: StorageState

    func register(on router: Router<AgentContext>) {
        router.get("/v1/storage") { _, _ in try Json.response(state.answer()) }
        router.post("/v1/storage/scan") { _, _ in try Json.response(state.scan(), status: .accepted) }
    }
}
