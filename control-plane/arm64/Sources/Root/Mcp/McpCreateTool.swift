import Foundation
import RootCore
import RootStore

/// create_vm: checks the call against the token (scopes, image, key, quotas, idempotency), then either stores it for a person to approve or runs it.
extension McpService {
    func createVm(_ input: McpCreateVmInput, token: McpTokenRecord) async throws -> McpToolReply {
        let onShared = try input.machine.map { isShared(try machine($0, for: token)) } ?? false
        if let missing = McpApprovalRules.missingCreateScope(gpuMemoryGb: input.gpuMemoryGb, onSharedMachine: onShared, has: token.scopes) { throw McpRefusal.scope(missing) }
        try validateImage(input.image)
        if let key = input.sshPublicKey { _ = try SshKeyRules.parse(key) }
        settle(token)
        if let key = input.idempotencyKey, let earlier = try requests.find(token: token.id, idempotencyKey: key) {
            return McpToolReply(payload: requestView(earlier, token: token), status: "replayed", target: input.machine)
        }
        guard throttle.allow("mcp-create:\(token.id)", limit: McpProtocol.createsPerMinute, seconds: 60) else {
            throw McpRefusal.busy("This token made 10 creates in the last minute: wait a minute before the next create_vm.")
        }
        let stored = McpStoredCreate(input: input)
        try checkQuota(stored.wish, token: token)
        let shape = McpApprovalRules.CreateShape(size: input.size, dimensions: input.dimensions, gpuMemoryGb: input.gpuMemoryGb, onSharedMachine: onShared)
        let reason = McpApprovalRules.reason(forCreate: shape, autoApprove: token.autoApprove)
        var params = stored.params
        params["ssh_public_key"] = input.sshPublicKey
        params["approval_reason"] = reason
        let (request, created) = try requests.create(NewMcpRequest(id: Self.newId("mr-"), tokenId: token.id, kind: .create, params: params, state: reason == nil ? .running : .pendingApproval,
                                                                  idempotencyKey: input.idempotencyKey, createdAt: clock.now, expiresAt: clock.now.addingTimeInterval(TimeInterval(McpRequestStore.approvalSeconds))))
        guard created else { return McpToolReply(payload: requestView(request, token: token), status: "replayed", target: input.machine) }
        if reason != nil { return needsApproval(request, target: input.machine) }
        try await launchCreate(request, token: token)
        let payload = try await waitFor(request.id, token: token, seconds: input.waitSeconds, pendingWord: "creating") { _, vm in vm?.state == "running" }
        return McpToolReply(payload: payload, target: input.machine, detail: ["request": request.id])
    }

    func needsApproval(_ request: McpRequestRow, target: String?) -> McpToolReply {
        var payload: [String: Any] = ["status": "needs_approval", "request_id": request.id, "message": McpDescribe.waitingForApproval]
        payload["reason"] = request.params["approval_reason"]
        return McpToolReply(payload: payload, status: "needs_approval", target: target, detail: ["request": request.id])
    }

    private func validateImage(_ image: String?) throws {
        guard let image, !AppCatalog.isApp(image) else { return }
        do {
            _ = try ImageCatalog.choose(image)
        } catch ImageChoiceError.notAvailable(let reason) {
            throw McpRefusal.invalid(reason)
        } catch {
            throw McpRefusal.invalid("image is not one of the listed images")
        }
    }

    /// Looks at the quotas now, so the AI learns at once; `admitCreate` looks again at the moment the slot is taken.
    private func checkQuota(_ wish: McpWish, token: McpTokenRecord) throws {
        let used = try ownership.usage(token: token.id, now: clock.now)
        if let refusal = McpQuotaCheck.refusal(token.quotas, used: used, wish: wish) { throw McpRefusal.quota(refusal) }
    }

    // MARK: running a stored create

    /// Takes the token's slot and a machine, then orders the VM. Used for a create that may run at once and for one a person just approved.
    /// Whatever goes wrong, the request ends `failed` with the plain reason and the slot is given back.
    func launchCreate(_ request: McpRequestRow, token: McpTokenRecord, approvedBy: String? = nil) async throws {
        var reserved: Int?
        do {
            guard let stored = McpStoredCreate(stored: request.params) else { throw McpRefusal.invalid("the stored request is damaged") }
            let (order, row) = try admitCreate(stored, request: request, token: token)
            reserved = row
            let command = try await workloads.create(actor: token.actor, request: order)
            try ownership.attach(row: row, command: command.id)
            try requests.setCommand(id: request.id, command: command.id)
            try requests.move(id: request.id, from: .approved, to: .running)
            record(token, tool: "create_vm", status: approvedBy == nil ? "ok" : "approved", target: order.machine, detail: Self.approvalDetail(request.id, approvedBy))
        } catch {
            if let reserved { try? ownership.remove(row: reserved) }
            let refusal = McpRefusal.from(error)
            try? requests.finish(id: request.id, state: .failed, result: ["message": refusal.message])
            throw refusal
        }
    }

    static func approvalDetail(_ request: String, _ approvedBy: String?) -> [String: String] {
        var detail = ["request": request]
        detail["approved_by"] = approvedBy
        return detail
    }

    /// One short critical section: the quotas are checked and the slot taken together, so no second create can slip in between.
    private func admitCreate(_ stored: McpStoredCreate, request: McpRequestRow, token: McpTokenRecord) throws -> (order: CreateWorkloadOperatorRequest, row: Int) {
        reserving.lock()
        defer { reserving.unlock() }
        try checkQuota(stored.wish, token: token)
        let order = try draft(stored, token: token)
        let chosen = try stored.machine.map { try machine($0, for: token).id } ?? workloads.chooseMachine(for: order, among: try unsharedMachineIds())
        let row = try ownership.reserve(NewMcpWorkload(tokenId: token.id, machineId: chosen, requestId: request.id, idempotencyKey: request.idempotencyKey, wish: stored.wish, createdAt: clock.now))
        return (order.placed(on: chosen), row)
    }

    /// A GPU memory limit is shared with containers, so such a create is a container; everything else is a VM.
    private func draft(_ stored: McpStoredCreate, token: McpTokenRecord) throws -> CreateWorkloadOperatorRequest {
        let gpu = stored.gpuMemoryGb != nil
        let name = stored.name ?? "mcp-" + Tokens.random(bytes: 6).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(6)
        return CreateWorkloadOperatorRequest(name: name, kind: gpu ? "container" : "vm", cpu: stored.dimensions.vcpu, ramMb: stored.dimensions.ramMb, diskGb: stored.dimensions.diskGb,
                                             gpuMode: gpu ? "container" : "none", machine: stored.machine, bundle: stored.image ?? ImageCatalog.blankId, gpuMemoryGb: stored.gpuMemoryGb)
    }

    /// With no machine named the choice is among the machines that are not shared: a shared PC is only used when the AI names it.
    private func unsharedMachineIds() throws -> Set<String> {
        let ids = Set(try machines.list(now: clock.now).filter { !isShared($0) }.map(\.id))
        guard !ids.isEmpty else { throw McpRefusal(kind: "failed", message: "No machine is available to this token: none is enrolled yet.") }
        return ids
    }
}
