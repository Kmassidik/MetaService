import Foundation
import MSCore
import RootCore
import RootStore

/// Keeps the SSH keys an operator gave for a VM and has the machine's helper put the full list in the VM, set up its SSH server and lock it to keys.
/// A change is always stored first and the answer comes at once; the apply runs in the background (`SshKeyApplier`). If the VM is stopped or the helper
/// cannot be reached the answer is simply "not applied yet", and the next heartbeat that shows the VM running tries again.
final class SshKeyService: @unchecked Sendable {
    static let sshdUnknown = "unknown"
    private static let runningState = "running"

    private let machines: MachineStore
    private let remoteMachines: RemoteMachineStore
    private let keys: SshKeyStore
    private let audit: AuditStore
    private let applier: SshKeyApplier
    private let clock: Clock

    init(machines: MachineStore, remoteMachines: RemoteMachineStore, keys: SshKeyStore, audit: AuditStore, client: AgentClient, clock: Clock) {
        self.machines = machines
        self.remoteMachines = remoteMachines
        self.keys = keys
        self.audit = audit
        self.applier = SshKeyApplier(keys: keys, client: client, clock: clock)
        self.clock = clock
    }

    // MARK: what the panel asks

    func view(machine: String, workload: String) throws -> SshKeyView {
        try currentView(machine: machine, workload: workload)
    }

    func add(actor: String, machine: String, workload: String, publicKey: String) throws -> SshKeyView {
        _ = try requireVM(machine: machine, workload: workload)
        let key = try SshKeyRules.parse(publicKey)
        try store { try keys.add(key, id: Self.newKeyId(), workload: workload, machine: machine, now: clock.now) }
        try audit.record(actor: actor, action: "ssh_key.add", target: machine, detail: ["workload": workload, "fingerprint": key.fingerprint], at: clock.now)
        try startApply(machine: machine, workload: workload)
        return try currentView(machine: machine, workload: workload)
    }

    func remove(actor: String, machine: String, workload: String, id: String) throws -> SshKeyView {
        _ = try requireVM(machine: machine, workload: workload)
        let fingerprint = try store { try keys.remove(id: id, workload: workload, machine: machine) }
        try audit.record(actor: actor, action: "ssh_key.remove", target: machine, detail: ["workload": workload, "fingerprint": fingerprint], at: clock.now)
        try startApply(machine: machine, workload: workload)
        return try currentView(machine: machine, workload: workload)
    }

    /// "Try again" in the panel: applies now, without waiting for the heartbeat or for the wait after a failure.
    func retry(actor: String, machine: String, workload: String) throws -> SshKeyView {
        guard try requireVM(machine: machine, workload: workload).state == Self.runningState else {
            throw ApiFailure(status: .conflict, code: "not_running", message: "Start the VM first, then try again.")
        }
        try audit.record(actor: actor, action: "ssh_key.retry", target: machine, detail: ["workload": workload], at: clock.now)
        applier.start(machine: machine, workload: workload)
        return try currentView(machine: machine, workload: workload)
    }

    /// Called with every heartbeat: starts an apply for each running VM of the machine whose keys the helper does not have yet.
    /// This is also what applies a stored change when a VM that was stopped becomes running. A failed apply waits its minute; one that is running is left alone.
    func applyPending(machine: String) async {
        guard let pending = try? keys.pendingWorkloads(machine: machine, now: clock.now), !pending.isEmpty else { return }
        for workload in pending where (try? requireVM(machine: machine, workload: workload).state) == Self.runningState {
            applier.start(machine: machine, workload: workload)
        }
    }

    // MARK: helpers

    /// Starts the background apply when the VM runs; a stopped VM keeps the change stored and unapplied.
    private func startApply(machine: String, workload: String) throws {
        guard try requireVM(machine: machine, workload: workload).state == Self.runningState else { return }
        applier.start(machine: machine, workload: workload)
    }

    private func currentView(machine: String, workload: String) throws -> SshKeyView {
        let (known, vm) = try requireMachineAndVM(machine: machine, workload: workload)
        let state = try keys.state(workload: workload, machine: machine)
        let progress = try keys.progress(workload: workload, machine: machine).atTime(Int(clock.now.timeIntervalSince1970))
        let office = try remoteMachines.get(machine)
        return SshKeyView(keys: try keys.list(workload: workload, machine: machine), applied: state.applied, sshd: state.sshd ?? Self.sshdUnknown,
                          sshdState: progress.phase.rawValue, sshdMessage: progress.message,
                          connect: SshConnectView(setting: known.settings?.sshJump, office: office, vmAddress: vm.address))
    }

    private func requireVM(machine: String, workload: String) throws -> WorkloadSummary {
        try requireMachineAndVM(machine: machine, workload: workload).vm
    }

    private func requireMachineAndVM(machine: String, workload: String) throws -> (machine: MachineSummary, vm: WorkloadSummary) {
        let known: MachineSummary
        do {
            known = try machines.get(id: machine, now: clock.now)
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
        guard let vm = known.workloads.first(where: { $0.id == workload }) else { throw ApiFailure.notFound }
        return (known, vm)
    }

    /// The store's refusals, in the words the panel shows.
    private func store<T>(_ change: () throws -> T) throws -> T {
        do {
            return try change()
        } catch SshKeyError.duplicate {
            throw ApiFailure(status: .conflict, code: "duplicate_key", message: "This key is already on this VM.")
        } catch SshKeyError.tooMany {
            throw ApiFailure(status: .conflict, code: "too_many_keys", message: "A VM can have at most \(SshKeyRules.maxKeysPerVM) keys. Remove one first.")
        } catch SshKeyError.notFound {
            throw ApiFailure.notFound
        }
    }

    private static func newKeyId() -> String {
        "key-" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(20)
    }
}
