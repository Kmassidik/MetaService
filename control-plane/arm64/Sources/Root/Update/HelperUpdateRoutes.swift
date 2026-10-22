import Foundation
import Hummingbird
import RootCore

/// "Update helper" on the machine page: replaces the helper program of one machine with the newest one the parent has.
struct HelperUpdateRoutes {
    let services: Services
    let guards: Guards

    func register(on group: RouterGroup<RootContext>) {
        group.post("/api/machines/{id}/update-helper", use: update)
    }

    func update(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        let id = try context.machineId()
        do {
            return try Json.response(try await services.helperUpdate.update(machine: id, actor: caller.name))
        } catch let failure as HelperUpdateFailure {
            throw failure.api
        } catch let failure as RemoteFailure {
            throw failure.api
        }
    }
}
