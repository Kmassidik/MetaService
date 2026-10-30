import Foundation
import RootCore
import RootStore

/// start_vm, stop_vm and delete_vm: only on a VM this token created. A delete waits for a person unless the token has auto_approve.
extension McpService {
    static let deleteWaitSeconds = 15

    func startVm(_ input: McpVmInput, token: McpTokenRecord) async throws -> McpToolReply {
        try await act(.start, input, token: token)
    }

    func stopVm(_ input: McpVmInput, token: McpTokenRecord) async throws -> McpToolReply {
        try await act(.stop, input, token: token)
    }

    func deleteVm(_ input: McpVmInput, token: McpTokenRecord) async throws -> McpToolReply {
        try await act(.delete, input, token: token)
    }

    private func act(_ action: WorkloadService.Action, _ input: McpVmInput, token: McpTokenRecord) async throws -> McpToolReply {
        settle(token)
        guard let row = try ownership.find(token: token.id, machine: input.machine, workload: input.vm), let live = liveVm(row) else { throw McpRefusal.noVm }
        let kind = McpRequestKind(rawValue: action.rawValue) ?? .stop
        let reason = action == .delete ? McpApprovalRules.reason(forDelete: token.autoApprove) : nil
        var params: [String: Any] = ["machine": input.machine, "vm": input.vm, "vm_name": live.vm.name, "machine_name": live.machine.name]
        params["approval_reason"] = reason
        let (request, _) = try requests.create(NewMcpRequest(id: Self.newId("mr-"), tokenId: token.id, kind: kind, params: params, state: reason == nil ? .running : .pendingApproval,
                                                            idempotencyKey: nil, createdAt: clock.now, expiresAt: clock.now.addingTimeInterval(TimeInterval(McpRequestStore.approvalSeconds))))
        let target = "\(input.machine)/\(input.vm)"
        if reason != nil { return needsApproval(request, target: target) }
        try await launchAction(request, token: token)
        let seconds = action == .delete ? Self.deleteWaitSeconds : input.waitSeconds
        let payload = try await waitFor(request.id, token: token, seconds: seconds, pendingWord: Self.pendingWord(action)) { _, vm in action != .start || vm?.state == "running" }
        return McpToolReply(payload: payload, target: target, detail: ["request": request.id])
    }

    private static func pendingWord(_ action: WorkloadService.Action) -> String {
        switch action {
        case .start: return "starting"
        case .stop: return "stopping"
        case .delete: return "deleting"
        }
    }

    /// Orders a stored start, stop or delete. The request ends `failed` with the plain reason when the machine will not take it.
    func launchAction(_ request: McpRequestRow, token: McpTokenRecord, approvedBy: String? = nil) async throws {
        do {
            guard let machine = request.params["machine"] as? String, let vm = request.params["vm"] as? String,
                  let action = WorkloadService.Action(rawValue: request.kind.rawValue) else { throw McpRefusal.invalid("the stored request is damaged") }
            guard try ownership.find(token: token.id, machine: machine, workload: vm) != nil else { throw McpRefusal.noVm }
            let command = try await workloads.act(actor: token.actor, machine: machine, workload: vm, action: action)
            terminal.vmActed(machine: machine, workload: vm, action: action)
            try requests.setCommand(id: request.id, command: command.id)
            try requests.move(id: request.id, from: .approved, to: .running)
            record(token, tool: "\(request.kind.rawValue)_vm", status: approvedBy == nil ? "ok" : "approved", target: "\(machine)/\(vm)", detail: Self.approvalDetail(request.id, approvedBy))
        } catch {
            let refusal = McpRefusal.from(error)
            try? requests.finish(id: request.id, state: .failed, result: ["message": refusal.message])
            throw refusal
        }
    }
}
