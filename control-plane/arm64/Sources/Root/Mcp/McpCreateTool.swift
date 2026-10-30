import Foundation
import RootCore
import RootStore

/// create_vm: checks the call against the caller (scopes, image, key, quotas, idempotency), then orders the VM and waits for it.
extension McpService {
    func createVm(_ input: McpCreateVmInput, caller: McpCaller) async throws -> McpToolReply {
        let onShared = try input.machine.map { isShared(try machine($0, for: caller)) } ?? false
        if let missing = McpScopeRules.missingCreateScope(gpuMemoryGb: input.gpuMemoryGb, onSharedMachine: onShared, has: caller.scopes) { throw McpRefusal.scope(missing) }
        try validateImage(input.image)
        if let key = input.sshPublicKey { _ = try SshKeyRules.parse(key) }
        settle(caller)
        if let key = input.idempotencyKey, let earlier = try requests.find(person: caller.person.id, idempotencyKey: key) {
            return McpToolReply(payload: requestView(earlier, caller: caller), status: "replayed", target: input.machine)
        }
        guard throttle.allow("mcp-create:\(caller.person.id)", limit: McpProtocol.createsPerMinute, seconds: 60) else {
            throw McpRefusal.busy("This person made 10 creates in the last minute: wait a minute before the next create_vm.")
        }
        let stored = McpStoredCreate(input: input)
        try checkQuota(stored.wish, caller: caller)
        var params = stored.params
        params["ssh_public_key"] = input.sshPublicKey
        let (request, created) = try requests.create(NewMcpRequest(id: Self.newId("mr-"), personId: caller.person.id, tokenId: caller.token.id, kind: .create, params: params,
                                                                  idempotencyKey: input.idempotencyKey, createdAt: clock.now))
        guard created else { return McpToolReply(payload: requestView(request, caller: caller), status: "replayed", target: input.machine) }
        try await launchCreate(request, caller: caller)
        let payload = try await waitFor(request.id, caller: caller, seconds: input.waitSeconds, pendingWord: "creating") { _, vm in vm?.state == "running" }
        return McpToolReply(payload: payload, target: input.machine, detail: ["request": request.id])
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
    private func checkQuota(_ wish: McpWish, caller: McpCaller) throws {
        let used = try ownership.usage(caller: caller.id, now: clock.now)
        if let refusal = McpQuotaCheck.refusal(caller.quotas, used: used, wish: wish) { throw McpRefusal.quota(refusal) }
    }

    // MARK: running a stored create

    /// Takes the person's slot and a machine, then orders the VM, with the creator record that is written once the machine has named it.
    /// Whatever goes wrong, the request ends `failed` with the plain reason and the slot is given back.
    func launchCreate(_ request: McpRequestRow, caller: McpCaller) async throws {
        var reserved: Int?
        do {
            guard let stored = McpStoredCreate(stored: request.params) else { throw McpRefusal.invalid("the stored request is damaged") }
            let (order, row) = try admitCreate(stored, request: request, caller: caller)
            reserved = row
            let command = try await workloads.create(actor: caller.actor, request: order, origin: caller.origin(request: request.id))
            try ownership.attach(row: row, command: command.id)
            try requests.setCommand(id: request.id, command: command.id)
            record(caller, tool: "create_vm", status: "ok", target: order.machine, detail: ["request": request.id])
        } catch {
            if let reserved { try? ownership.remove(row: reserved) }
            let refusal = McpRefusal.from(error)
            try? requests.finish(id: request.id, state: .failed, result: ["message": refusal.message])
            throw refusal
        }
    }

    /// One short critical section: the quotas are checked and the slot taken together, so no second create can slip in between.
    private func admitCreate(_ stored: McpStoredCreate, request: McpRequestRow, caller: McpCaller) throws -> (order: CreateWorkloadOperatorRequest, row: Int) {
        reserving.lock()
        defer { reserving.unlock() }
        try checkQuota(stored.wish, caller: caller)
        let order = try draft(stored, caller: caller)
        let chosen = try stored.machine.map { try machine($0, for: caller).id } ?? workloads.chooseMachine(for: order, among: try unsharedMachineIds())
        let row = try ownership.reserve(NewMcpWorkload(personId: caller.person.id, tokenId: caller.token.id, machineId: chosen, requestId: request.id, idempotencyKey: request.idempotencyKey, wish: stored.wish, createdAt: clock.now))
        return (order.placed(on: chosen), row)
    }

    /// A GPU memory limit is shared with containers, so such a create is a container; everything else is a VM.
    private func draft(_ stored: McpStoredCreate, caller: McpCaller) throws -> CreateWorkloadOperatorRequest {
        let gpu = stored.gpuMemoryGb != nil
        let name = stored.name ?? "mcp-" + Tokens.random(bytes: 6).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(6)
        return CreateWorkloadOperatorRequest(name: name, kind: gpu ? "container" : "vm", cpu: stored.dimensions.vcpu, ramMb: stored.dimensions.ramMb, diskGb: stored.dimensions.diskGb,
                                             gpuMode: gpu ? "container" : "none", machine: stored.machine, bundle: stored.image ?? ImageCatalog.blankId, gpuMemoryGb: stored.gpuMemoryGb)
    }

    /// With no machine named the choice is among the machines that are not shared: a shared PC is only used when the AI names it.
    private func unsharedMachineIds() throws -> Set<String> {
        let ids = Set(try machines.list(now: clock.now).filter { !isShared($0) }.map(\.id))
        guard !ids.isEmpty else { throw McpRefusal(kind: "failed", message: "No machine is available to this person: none is enrolled yet.") }
        return ids
    }
}
