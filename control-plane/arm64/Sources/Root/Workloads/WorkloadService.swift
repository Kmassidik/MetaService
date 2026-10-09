import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// Turns an operator's wish into a command on one machine, and follows it until the Agent says it is done.
final class WorkloadService: @unchecked Sendable {
    private let machines: MachineStore
    private let commands: CommandStore
    private let audit: AuditStore
    private let client: AgentClient
    private let clock: Clock
    private let bundles: BundleStore
    private let chatAccess: ChatAccessStore
    private let secrets: SecretBox
    private let creating = NSLock()
    private static let pollSeconds: UInt64 = 1
    private static let giveUpAfterSeconds = 20 * 60
    private static let lostContactAfterPolls = 300

    init(machines: MachineStore, commands: CommandStore, audit: AuditStore, client: AgentClient, clock: Clock, bundles: BundleStore, chatAccess: ChatAccessStore, secrets: SecretBox) {
        self.bundles = bundles
        self.chatAccess = chatAccess
        self.secrets = secrets
        self.machines = machines
        self.commands = commands
        self.audit = audit
        self.client = client
        self.clock = clock
    }

    // MARK: asking for things

    func create(actor: String, request: CreateWorkloadOperatorRequest) async throws -> CommandRow {
        let (machine, id) = try reserve(actor: actor, request: request)
        var body: [String: Any] = ["command_id": id, "name": request.name, "kind": request.kind, "cpu": request.cpu, "ram_mb": request.ramMb, "disk_gb": request.diskGb, "gpu_mode": request.gpuMode]
        body["image"] = request.image ?? (try? machines.get(id: machine, now: clock.now))?.settings?.vmImage
        return try await send(id, machine: machine, method: "POST", path: "/v1/workloads", body: body)
    }

    /// Chooses the machine and writes the command in one step, so two requests made at once cannot both count the same free room.
    private func reserve(actor: String, request: CreateWorkloadOperatorRequest) throws -> (machine: String, id: String) {
        creating.lock()
        defer { creating.unlock() }
        let now = clock.now
        let machine = try Placement.choose(try candidates(now), PlacementWish(kind: request.kind, gpuMode: request.gpuMode, ramMb: request.ramMb, diskGb: request.diskGb, onlyMachine: request.machine))
        let id = Self.newCommandId()
        let params = ["name": request.name, "kind": request.kind, "cpu": String(request.cpu), "ram_mb": String(request.ramMb), "disk_gb": String(request.diskGb), "gpu_mode": request.gpuMode]
        try commands.create(id: id, machine: machine, workloadId: nil, type: "create", params: params, actor: actor, now: now)
        try audit.record(actor: actor, action: "workload.create", target: machine, detail: ["name": request.name, "command": id], at: now)
        return (machine, id)
    }

    enum Action: String { case start, stop, delete }

    func act(actor: String, machine: String, workload: String, action: Action) async throws -> CommandRow {
        let known: MachineSummary
        do {
            known = try machines.get(id: machine, now: clock.now)
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
        guard known.workloads.contains(where: { $0.id == workload }) else { throw ApiFailure.notFound }
        let id = Self.newCommandId()
        try commands.create(id: id, machine: machine, workloadId: workload, type: action.rawValue, params: [:], actor: actor, now: clock.now)
        try audit.record(actor: actor, action: "workload.\(action.rawValue)", target: machine, detail: ["workload": workload, "command": id], at: clock.now)
        let path = action == .delete ? "/v1/workloads/\(workload)" : "/v1/workloads/\(workload)/\(action.rawValue)"
        return try await send(id, machine: machine, method: action == .delete ? "DELETE" : "POST", path: path, body: nil, commandId: id)
    }

    /// Installs (or upgrades, or rolls back) the pinned chat bundle on a machine or one of its workloads.
    func installBundle(actor: String, machine: String, workload: String?) async throws -> CommandRow {
        guard let version = try bundles.pinned() else { throw ApiFailure(status: .conflict, code: "no_bundle_pinned", message: "pin a chat bundle version first") }
        guard let bundle = try bundles.find(version: version, platform: "noarch") else { throw ApiFailure(status: .conflict, code: "bundle_missing", message: "the pinned bundle file is not on the Root machine") }
        let known: MachineSummary
        do { known = try machines.get(id: machine, now: clock.now) } catch MachineError.notFound { throw ApiFailure.notFound }
        guard workload == nil || known.workloads.contains(where: { $0.id == workload }) else { throw ApiFailure.notFound }
        let id = Self.newCommandId()
        try commands.create(id: id, machine: machine, workloadId: workload, type: "bundle_install", params: ["version": version], actor: actor, now: clock.now)
        try audit.record(actor: actor, action: "bundle.install", target: machine, detail: ["version": version, "workload": workload ?? "", "command": id], at: clock.now)
        var body: [String: Any] = ["command_id": id, "version": version, "sha256": bundle.sha256]
        body["workload_id"] = workload
        return try await send(id, machine: machine, method: "POST", path: "/v1/bundle/install", body: body)
    }

    /// After a restart, keep following whatever was still running.
    func resume() {
        for command in (try? commands.unfinished()) ?? [] { follow(command.id, machine: command.machine) }
    }

    // MARK: sending and following

    private func candidates(_ now: Date) throws -> [PlacementMachine] {
        try machines.list(now: now).map { machine in
            let promised = (try? commands.promised(machine: machine.id)) ?? (ramMb: 0, diskGb: 0)
            let settings = machine.settings
            let running = machine.workloads.filter { ["running", "provisioning"].contains($0.state) }.count
            return PlacementMachine(id: machine.id, online: machine.state != "offline",
                                    capabilities: settings?.limiting(machine.capabilities) ?? machine.capabilities,
                                    freeRamMb: max(0, (machine.freeRamMb ?? 0) - promised.ramMb), freeDiskGb: max(0, (machine.freeDiskGb ?? 0) - promised.diskGb),
                                    hasProblems: !machine.problems.isEmpty, atMaxVMs: settings?.isFull(running: running) ?? false)
        }
    }

    private func send(_ id: String, machine: String, method: String, path: String, body: [String: Any]?, commandId: String? = nil) async throws -> CommandRow {
        let reply: AgentReply
        do {
            reply = try await client.call(machine: machine, method: method, path: path, body: body, commandId: commandId)
        } catch {
            try finish(id, state: "failed", result: ["error": "the machine could not be reached"])
            throw ApiFailure(status: .badGateway, code: "machine_unreachable", message: "the machine could not be reached")
        }
        guard reply.status == 202 else { throw try refused(id, reply) }
        try commands.update(id: id, state: "running", result: nil, now: clock.now)
        follow(id, machine: machine)
        return try commands.get(id)!
    }

    /// The Agent said no. Pass its numbers on, and record the command as failed.
    private func refused(_ id: String, _ reply: AgentReply) throws -> Error {
        let detail = reply.json?["error"] as? [String: Any]
        try finish(id, state: "failed", result: ["error": detail?["message"] as? String ?? "the machine refused"])
        guard reply.status == 409, let detail, let resource = detail["resource"] as? String, let needed = detail["needed"] as? Int, let free = detail["free"] as? Int else {
            return ApiFailure(status: .badGateway, code: "machine_refused", message: "the machine refused the request")
        }
        return PlacementRefusal(code: detail["code"] as? String ?? "not_enough_room", message: detail["message"] as? String ?? "refused", resource: resource, needed: needed, free: free)
    }

    private func follow(_ id: String, machine: String) {
        Task.detached { [self] in
            var silent = 0
            for _ in 0..<Self.giveUpAfterSeconds {
                try? await Task.sleep(nanoseconds: Self.pollSeconds * 1_000_000_000)
                guard let reply = try? await client.call(machine: machine, method: "GET", path: "/v1/commands/\(id)") else {
                    silent += 1
                    guard silent < Self.lostContactAfterPolls else { return lost(id, "lost contact with the machine") }
                    continue
                }
                silent = 0
                guard let state = reply.json?["state"] as? String, ["succeeded", "failed"].contains(state) else { continue }
                return done(id, state, reply.json?["result"] as? [String: Any])
            }
            lost(id, "gave up waiting")
        }
    }

    private func done(_ id: String, _ state: String, _ result: [String: Any]?) {
        var text = (result ?? [:]).compactMapValues { $0 as? String }
        keepChatKey(id, &text)
        try? finish(id, state: state, result: text)
    }

    /// A finished install hands over the chat's access key. It goes into the sealed key store and never into the command record.
    private func keepChatKey(_ id: String, _ result: inout [String: String]) {
        guard let key = result.removeValue(forKey: "chat_key"), let row = try? commands.get(id), row.type == "bundle_install" else { return }
        let target = row.workloadId.map { "\(row.machine)/\($0)" } ?? row.machine
        guard let sealed = try? secrets.seal(key) else { return }
        try? chatAccess.set(target: target, sealedKey: sealed, port: Int(result["port"] ?? "") ?? 9200, now: clock.now)
    }

    private func lost(_ id: String, _ why: String) {
        try? finish(id, state: "failed", result: ["error": why])
    }

    private func finish(_ id: String, state: String, result: [String: String]) throws {
        try commands.update(id: id, state: state, result: result, now: clock.now)
        guard let row = try commands.get(id) else { return }
        try audit.record(actor: "root", action: "workload.\(row.type)_\(state)", target: row.machine, detail: ["command": id].merging(result) { $1 }, at: clock.now)
    }

    private static func newCommandId() -> String {
        "rc-" + Tokens.random(bytes: 9).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(12)
    }
}
