import Foundation
import MSCore
import RootCore
import RootStore

/// What the panel sees of a VM's keys: who may log in as root there, and whether the machine's helper has that list yet.
struct SshKeyView: Encodable {
    let keys: [SshKeyRecord]
    let applied: Bool
    let sshd: String
}

/// Keeps the SSH keys an operator gave for a VM and sends the full list to the machine's helper whenever the VM runs.
/// A change is always stored first; if the VM is stopped or the helper cannot be reached the answer is simply "not applied yet",
/// and the next heartbeat that shows the VM running tries again.
final class SshKeyService: @unchecked Sendable {
    static let sshdUnknown = "unknown"
    private static let knownSshdStates: Set<String> = ["running", "installed", "missing"]
    private static let runningState = "running"

    private let machines: MachineStore
    private let keys: SshKeyStore
    private let audit: AuditStore
    private let client: AgentClient
    private let clock: Clock
    private let busy = NSLock()
    private var applying = Set<String>()

    init(machines: MachineStore, keys: SshKeyStore, audit: AuditStore, client: AgentClient, clock: Clock) {
        self.machines = machines
        self.keys = keys
        self.audit = audit
        self.client = client
        self.clock = clock
    }

    // MARK: what the panel asks

    func view(machine: String, workload: String) throws -> SshKeyView {
        _ = try requireVM(machine: machine, workload: workload)
        return try currentView(machine: machine, workload: workload)
    }

    func add(actor: String, machine: String, workload: String, publicKey: String) async throws -> SshKeyView {
        _ = try requireVM(machine: machine, workload: workload)
        let key = try SshKeyRules.parse(publicKey)
        try store { try keys.add(key, id: Self.newKeyId(), workload: workload, machine: machine, now: clock.now) }
        try audit.record(actor: actor, action: "ssh_key.add", target: machine, detail: ["workload": workload, "fingerprint": key.fingerprint], at: clock.now)
        try await apply(machine: machine, workload: workload)
        return try currentView(machine: machine, workload: workload)
    }

    func remove(actor: String, machine: String, workload: String, id: String) async throws -> SshKeyView {
        _ = try requireVM(machine: machine, workload: workload)
        let fingerprint = try store { try keys.remove(id: id, workload: workload, machine: machine) }
        try audit.record(actor: actor, action: "ssh_key.remove", target: machine, detail: ["workload": workload, "fingerprint": fingerprint], at: clock.now)
        try await apply(machine: machine, workload: workload)
        return try currentView(machine: machine, workload: workload)
    }

    // MARK: applying

    /// Called with every heartbeat: sends the list to each running VM of the machine whose keys the helper does not have yet.
    /// This is also what applies a stored change when a VM that was stopped becomes running.
    func applyPending(machine: String) async {
        guard let pending = try? keys.pendingWorkloads(machine: machine), !pending.isEmpty else { return }
        for workload in pending where claimApply(machine: machine, workload: workload) {
            defer { releaseApply(machine: machine, workload: workload) }
            // A failure here (the VM went away, the store was busy) leaves the VM "not applied", which is what the next heartbeat retries.
            try? await apply(machine: machine, workload: workload)
        }
    }

    /// Sends the complete list to a running VM and records how it went. A VM that is not running, or a helper that says no, leaves it "not applied".
    private func apply(machine: String, workload: String) async throws {
        guard try requireVM(machine: machine, workload: workload).state == Self.runningState else { return }
        let snapshot = try keys.snapshot(workload: workload, machine: machine)
        let reply = try? await client.call(machine: machine, method: "PUT", path: "/v1/workloads/\(workload)/ssh-keys", body: ["keys": snapshot.lines])
        let accepted = reply?.status == 200 && reply?.json?["applied"] as? Int == snapshot.lines.count
        let sshd = (reply?.json?["sshd"] as? String).flatMap { Self.knownSshdStates.contains($0) ? $0 : nil }
        guard accepted else { return }
        try keys.recordApply(workload: workload, machine: machine, revision: snapshot.revision, applied: true, sshd: sshd)
    }

    private func claimApply(machine: String, workload: String) -> Bool {
        busy.withLock { applying.insert("\(machine)/\(workload)").inserted }
    }

    private func releaseApply(machine: String, workload: String) {
        busy.withLock { _ = applying.remove("\(machine)/\(workload)") }
    }

    // MARK: helpers

    private func currentView(machine: String, workload: String) throws -> SshKeyView {
        let state = try keys.state(workload: workload, machine: machine)
        return SshKeyView(keys: try keys.list(workload: workload, machine: machine), applied: state.applied, sshd: state.sshd ?? Self.sshdUnknown)
    }

    private func requireVM(machine: String, workload: String) throws -> WorkloadSummary {
        let known: MachineSummary
        do {
            known = try machines.get(id: machine, now: clock.now)
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
        guard let vm = known.workloads.first(where: { $0.id == workload }) else { throw ApiFailure.notFound }
        return vm
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
