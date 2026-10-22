import Foundation
import Hummingbird
import MSCore
import RootCore

/// The panel's SSH keys for one VM: list, add, remove. The key itself is only ever sent to the machine's helper, never back to the panel.
struct SshKeyRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 120
    static let changesPerMinute = 30
    /// Longer than any key may be, so a too-long paste gets the rules' plain refusal and not a generic one.
    private static let maxPastedCharacters = 4096

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/workloads/{workload}/ssh-keys", use: list)
        group.post("/api/machines/{id}/workloads/{workload}/ssh-keys", use: add)
        group.delete("/api/machines/{id}/workloads/{workload}/ssh-keys/{key}", use: remove)
    }

    private func list(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("ssh-keys-read", per: context, max: Self.readsPerMinute, seconds: 60)
        let (machine, workload) = try vm(context)
        return try Json.response(try services.sshKeys.view(machine: machine, workload: workload))
    }

    private func add(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("ssh-keys-change", per: context, max: Self.changesPerMinute, seconds: 60)
        let (machine, workload) = try vm(context)
        let pasted = try PastedKey(body: try await guards.body(request)).text
        return try Json.response(try await services.sshKeys.add(actor: caller.name, machine: machine, workload: workload, publicKey: pasted), status: .created)
    }

    private func remove(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("ssh-keys-change", per: context, max: Self.changesPerMinute, seconds: 60)
        let (machine, workload) = try vm(context)
        guard let key = context.parameters.get("key"), Ids.isValid(key) else { throw ApiFailure.notFound }
        return try Json.response(try await services.sshKeys.remove(actor: caller.name, machine: machine, workload: workload, id: key))
    }

    private func vm(_ context: RootContext) throws -> (machine: String, workload: String) {
        guard let machine = context.parameters.get("id"), let workload = context.parameters.get("workload"), Ids.isValid(machine), Ids.isValid(workload) else { throw ApiFailure.notFound }
        return (machine, workload)
    }

    private struct PastedKey {
        let text: String

        init(body: Data) throws {
            let object = try StrictObject(data: body, allowed: ["public_key"])
            text = try object.string("public_key", maxLength: SshKeyRoutes.maxPastedCharacters)
        }
    }
}
