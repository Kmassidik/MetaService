import Foundation
import RootCore
import RootStore

/// start_vm, stop_vm and delete_vm: only on a VM the caller's person created. They run at once; a delete needs the `destroy` scope.
extension McpService {
    static let deleteWaitSeconds = 15

    func startVm(_ input: McpVmInput, caller: McpCaller) async throws -> McpToolReply {
        try await act(.start, input, caller: caller)
    }

    func stopVm(_ input: McpVmInput, caller: McpCaller) async throws -> McpToolReply {
        try await act(.stop, input, caller: caller)
    }

    func deleteVm(_ input: McpVmInput, caller: McpCaller) async throws -> McpToolReply {
        try await act(.delete, input, caller: caller)
    }

    private func act(_ action: WorkloadService.Action, _ input: McpVmInput, caller: McpCaller) async throws -> McpToolReply {
        settle(caller)
        guard let row = try ownership.find(person: caller.person.id, machine: input.machine, workload: input.vm), let live = liveVm(row) else { throw McpRefusal.noVm }
        let kind = McpRequestKind(rawValue: action.rawValue) ?? .stop
        let params: [String: Any] = ["machine": input.machine, "vm": input.vm, "vm_name": live.vm.name, "machine_name": live.machine.name]
        let (request, _) = try requests.create(NewMcpRequest(id: Self.newId("mr-"), personId: caller.person.id, tokenId: caller.token.id, kind: kind, params: params, idempotencyKey: nil, createdAt: clock.now))
        try await launchAction(request, caller: caller)
        let seconds = action == .delete ? Self.deleteWaitSeconds : input.waitSeconds
        let payload = try await waitFor(request.id, caller: caller, seconds: seconds, pendingWord: Self.pendingWord(action)) { _, vm in action != .start || vm?.state == "running" }
        return McpToolReply(payload: payload, target: "\(input.machine)/\(input.vm)", detail: ["request": request.id])
    }

    private static func pendingWord(_ action: WorkloadService.Action) -> String {
        switch action {
        case .start: return "starting"
        case .stop: return "stopping"
        case .delete: return "deleting"
        }
    }

    /// Orders a start, stop or delete. The request ends `failed` with the plain reason when the machine will not take it.
    func launchAction(_ request: McpRequestRow, caller: McpCaller) async throws {
        do {
            guard let machine = request.params["machine"] as? String, let vm = request.params["vm"] as? String,
                  let action = WorkloadService.Action(rawValue: request.kind.rawValue) else { throw McpRefusal.invalid("the stored request is damaged") }
            guard try ownership.find(person: caller.person.id, machine: machine, workload: vm) != nil else { throw McpRefusal.noVm }
            let command = try await workloads.act(actor: caller.actor, machine: machine, workload: vm, action: action)
            terminal.vmActed(machine: machine, workload: vm, action: action)
            try requests.setCommand(id: request.id, command: command.id)
            record(caller, tool: "\(request.kind.rawValue)_vm", status: "ok", target: "\(machine)/\(vm)", detail: ["request": request.id])
        } catch {
            let refusal = McpRefusal.from(error)
            try? requests.finish(id: request.id, state: .failed, result: ["message": refusal.message])
            throw refusal
        }
    }
}
