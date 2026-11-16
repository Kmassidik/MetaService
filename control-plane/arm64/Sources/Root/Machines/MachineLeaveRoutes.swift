import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// "Clean the computer too" in the Remove dialog: asks the machine's own helper to take MetaService off that computer (it stops its helper and WireGuard, removes its boot
/// entries and its join folder) with the sudo password the operator typed. The password is in this request only: it is passed to the helper once and is never logged, audited or kept.
/// Only the fact that a clean-up was asked for, and how it ended, is audited.
struct MachineLeaveRoutes {
    let services: Services
    let guards: Guards

    static let leavesPerMinute = 6
    static let longestPassword = 256
    /// The helper's own root step is bounded at 60 seconds.
    static let helperSeconds: TimeInterval = 75
    static let helperPath = "/v1/leave"

    func register(on group: RouterGroup<RootContext>) {
        group.post("/api/machines/{id}/leave", use: leave)
    }

    /// What the helper's answer means for the panel. A pure function, so the wording is tested.
    static func outcome(status: Int, errorCode: String?, message: String?) -> Result<Void, ApiFailure> {
        switch (status, errorCode) {
        case (200, _): return .success(())
        case (409, "leave_failed"): return .failure(ApiFailure(status: .conflict, code: "leave_failed", message: message ?? "the computer could not be cleaned"))
        case (404, "not_joined"): return .failure(ApiFailure(status: .conflict, code: "not_joined", message: "this computer was not added through Share a PC, so there is nothing to clean on it"))
        case (404, _): return .failure(ApiFailure(status: .conflict, code: "old_helper", message: "this computer's helper is too old to clean itself"))
        default: return .failure(ApiFailure(status: .badGateway, code: "unreachable", message: "the computer did not answer, so nothing was cleaned"))
        }
    }

    private func leave(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("machine-leave", per: context, max: Self.leavesPerMinute, seconds: 60)
        let id = try context.machineId()
        let body = try await guards.body(request)
        let password = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["sudo_password"] as? String ?? ""
        guard password.utf8.count <= Self.longestPassword, !password.contains("\n") else { throw ApiFailure.invalid("the password is not acceptable") }
        do {
            _ = try services.machines.get(id: id, now: services.clock.now)
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
        let client = AgentClient(machines: services.machines, secrets: services.secrets, tunnels: services.tunnelPorts)
        let reply = try? await client.call(machine: id, method: "POST", path: Self.helperPath, body: ["sudo_password": password], timeout: Self.helperSeconds)
        let error = reply?.json?["error"] as? [String: Any]
        let decided = reply.map { Self.outcome(status: $0.status, errorCode: error?["code"] as? String, message: error?["message"] as? String) } ?? Self.outcome(status: 0, errorCode: nil, message: nil)
        try services.audit.record(actor: caller.name, action: "machine.leave", target: id, detail: ["result": Self.code(of: decided)], at: services.clock.now)
        switch decided {
        case .success: return try Json.response(["leaving": true])
        case .failure(let failure): throw failure
        }
    }

    private static func code(of result: Result<Void, ApiFailure>) -> String {
        if case .failure(let failure) = result { return failure.code }
        return "ok"
    }
}
