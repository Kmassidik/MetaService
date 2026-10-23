import Foundation
import MSCore
import RootCore
import RootStore

/// Keeps the app an operator wants inside a VM (OpenClaw, Hermes) and has the machine's helper install it, in the background (`AppApplier`).
/// A change is always stored first and the answer comes at once. If the VM is stopped or the helper cannot be reached the app is simply "not started yet",
/// and the next heartbeat that shows the VM running tries again.
final class AppService: @unchecked Sendable {
    private static let runningState = "running"

    private let machines: MachineStore
    private let apps: AppStateStore
    private let audit: AuditStore
    private let applier: AppApplier
    private let clock: Clock

    init(machines: MachineStore, apps: AppStateStore, audit: AuditStore, client: AgentClient, clock: Clock) {
        self.machines = machines
        self.apps = apps
        self.audit = audit
        self.applier = AppApplier(apps: apps, client: client, audit: audit, clock: clock)
        self.clock = clock
    }

    /// The VM is gone: so is the app wished for it.
    func forget(workload: String, machine: String) {
        try? apps.forget(workload: workload, machine: machine)
    }

    func view(machine: String, workload: String) throws -> AppView {
        _ = try requireVM(machine: machine, workload: workload)
        return try currentView(machine: machine, workload: workload)
    }

    /// "Try again" in the panel: starts now, without waiting for the heartbeat or for the wait after a failure.
    func retry(actor: String, machine: String, workload: String) throws -> AppView {
        let vm = try requireVM(machine: machine, workload: workload)
        guard try apps.record(workload: workload, machine: machine) != nil else {
            throw ApiFailure(status: .conflict, code: "no_app", message: "This VM has no app to set up.")
        }
        guard vm.state == Self.runningState else {
            throw ApiFailure(status: .conflict, code: "not_running", message: "Start the VM first, then try again.")
        }
        try audit.record(actor: actor, action: "app.retry", target: machine, detail: ["workload": workload], at: clock.now)
        applier.start(machine: machine, workload: workload)
        return try currentView(machine: machine, workload: workload)
    }

    /// A create that asked for an app has succeeded: remember the wish, and start the install as the new VM runs.
    func created(app: String, machine: String, workload: String) {
        guard AppCatalog.isApp(app), (try? apps.recordIntent(app: app, workload: workload, machine: machine, now: clock.now)) != nil else { return }
        guard (try? requireVM(machine: machine, workload: workload).state) == Self.runningState else { return }
        applier.start(machine: machine, workload: workload)
    }

    /// Called with every heartbeat: starts an install for each running VM of the machine that wants one and has not got it.
    /// This is also what starts a stored wish when a VM that was stopped becomes running. A failed install waits its minute; one that is running is left alone.
    func startPending(machine: String) {
        guard let pending = try? apps.pendingWorkloads(machine: machine, now: clock.now), !pending.isEmpty else { return }
        for workload in pending where (try? requireVM(machine: machine, workload: workload).state) == Self.runningState {
            applier.start(machine: machine, workload: workload)
        }
    }

    private func currentView(machine: String, workload: String) throws -> AppView {
        guard let record = try apps.record(workload: workload, machine: machine) else { return .none }
        return AppView(record, at: Int(clock.now.timeIntervalSince1970))
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
}
