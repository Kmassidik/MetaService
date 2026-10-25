import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// What the panel's Storage tab reads and the button that asks for a new scan. The map is a read (the operator's session and the right Host);
/// a scan makes the machine work, so it is a write (also the exact Origin and the CSRF header) and limited per machine in the service.
struct StorageRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 60

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/storage", use: storage)
        group.post("/api/machines/{id}/storage/scan", use: scan)
    }

    private func storage(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("machine-storage", per: context, max: Self.readsPerMinute, seconds: 60)
        let id = try context.machineId()
        do {
            return try Json.response(try await services.storage.reply(for: id))
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
    }

    /// Answers 202 with the same envelope as the read: the scan runs on the machine in the background.
    private func scan(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorWrite(request)
        let id = try context.machineId()
        do {
            return try Json.response(try await services.storage.scan(for: id), status: .accepted)
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
    }
}
