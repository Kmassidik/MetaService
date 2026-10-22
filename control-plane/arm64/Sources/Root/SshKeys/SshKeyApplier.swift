import Foundation
import MSCore
import RootCore
import RootStore

/// Sends a VM's full key list to its machine's helper and asks it to set up the SSH server, as a detached task: an install can take minutes,
/// so no web request waits for it. The store shows "installing" from the moment an apply starts until it ends.
final class SshKeyApplier: @unchecked Sendable {
    /// The helper gives an install five minutes; this is that plus a margin, so the helper's own answer arrives before the Root stops waiting.
    static let callSeconds: TimeInterval = 330
    /// Keys changed while an apply was running: it is repeated until the list holds still. Changes are limited to 30 a minute and 20 keys, so this bound is never reached by people; it only stops a runaway loop.
    static let maxPasses = 25

    private let keys: SshKeyStore
    private let client: AgentClient
    private let clock: Clock
    private let busy = NSLock()
    private var applying = Set<String>()

    init(keys: SshKeyStore, client: AgentClient, clock: Clock) {
        self.keys = keys
        self.client = client
        self.clock = clock
    }

    /// Marks the VM "installing" and runs the apply in the background. Nothing happens when one is already running for this VM: it picks up the newest list by itself.
    func start(machine: String, workload: String) {
        guard claim(machine: machine, workload: workload) else { return }
        do {
            try keys.beginApply(workload: workload, machine: machine, now: clock.now)
        } catch {
            release(machine: machine, workload: workload)
            return
        }
        Task.detached { [self] in
            defer { release(machine: machine, workload: workload) }
            await run(machine: machine, workload: workload)
        }
    }

    /// The apply itself, awaited. Ends the "installing" phase whatever happens, with the plain reason when it failed.
    func run(machine: String, workload: String) async {
        var failure: String?
        do {
            failure = try await passes(machine: machine, workload: workload)
        } catch {
            failure = SshdProgress.unclearFailureMessage
        }
        // Finishing can only fail when the store is busy or gone; the phase then times out by itself (SshdProgress.atTime) and the heartbeat tries again.
        try? keys.finishApply(workload: workload, machine: machine, failure: failure, now: clock.now)
    }

    /// Sends the list; sends it again when keys were added or removed meanwhile. Returns the plain reason of a failure, nil otherwise.
    private func passes(machine: String, workload: String) async throws -> String? {
        for _ in 0..<Self.maxPasses {
            let snapshot = try keys.snapshot(workload: workload, machine: machine)
            let outcome = await send(snapshot, machine: machine, workload: workload)
            if let failure = try record(outcome, snapshot: snapshot, machine: machine, workload: workload) { return failure }
            guard try keys.snapshot(workload: workload, machine: machine).revision != snapshot.revision else { return nil }
        }
        return nil
    }

    private func send(_ snapshot: SshKeySnapshot, machine: String, workload: String) async -> SshApplyOutcome {
        let reply = try? await client.call(machine: machine, method: "PUT", path: "/v1/workloads/\(workload)/ssh-keys",
                                           body: ["keys": snapshot.lines, "install_sshd": true], timeout: Self.callSeconds)
        return SshApplyOutcome.read(status: reply?.status, json: reply?.json, expectedKeys: snapshot.lines.count)
    }

    /// Stores what the helper said and returns the plain reason when the SSH server could not be set up.
    private func record(_ outcome: SshApplyOutcome, snapshot: SshKeySnapshot, machine: String, workload: String) throws -> String? {
        switch outcome {
        case .applied(let sshd):
            try keys.recordApply(workload: workload, machine: machine, revision: snapshot.revision, applied: true, sshd: sshd)
            return nil
        case .sshdFailed(let message): return message
        case .helperTooOld: return SshdProgress.oldHelperMessage
        case .notApplied: return nil
        }
    }

    private func claim(machine: String, workload: String) -> Bool {
        busy.withLock { applying.insert("\(machine)/\(workload)").inserted }
    }

    private func release(machine: String, workload: String) {
        busy.withLock { _ = applying.remove("\(machine)/\(workload)") }
    }
}
