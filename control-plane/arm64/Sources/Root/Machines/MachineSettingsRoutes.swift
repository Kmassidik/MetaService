import Foundation
import Hummingbird
import RootCore
import RootStore

/// Changing a machine's settings after it was added. Same checks as every operator write: the session, the exact Origin, the CSRF header.
struct MachineSettingsRoutes {
    let services: Services
    let guards: Guards

    func register(on group: RouterGroup<RootContext>) {
        group.patch("/api/machines/{id}/settings", use: change)
    }

    private func change(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        let id = try context.machineId()
        let patch = try MachineSettingsPatch(body: try await guards.body(request))
        let next = try patch.applying(to: try currentSettings(of: id))
        try rename(id, to: patch.name)
        try services.machineSettings.save(next, machine: id)
        try services.audit.record(actor: caller.name, action: "machine.settings", target: id, detail: ["fields": patch.changed.joined(separator: ",")], at: services.clock.now)
        return try Json.response(try services.machineDetails.get(id: id))
    }

    /// The settings the machine has now. A machine that was never given any starts from the defaults. A machine that does not exist is "no such thing".
    private func currentSettings(of id: String) throws -> MachineSettings {
        do {
            return try services.machines.get(id: id, now: services.clock.now).settings ?? MachineSettings()
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
    }

    private func rename(_ id: String, to name: String?) throws {
        guard let name else { return }
        do {
            try services.machines.rename(id: id, to: name)
        } catch MachineError.exists {
            throw ApiFailure(status: .conflict, code: "machine_exists", message: "another machine already has that name")
        }
    }
}
