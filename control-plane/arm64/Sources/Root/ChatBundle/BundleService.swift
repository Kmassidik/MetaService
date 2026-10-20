import Foundation
import RootCore
import RootStore

/// Keeps every machine and workload that already has the chat bundle on the pinned version: after a new pin, or a rollback,
/// each one gets an install command within a few seconds. A first install is always the operator's own request.
final class BundleService: @unchecked Sendable {
    private let machines: MachineStore
    private let commands: CommandStore
    private let bundles: BundleStore
    private let workloads: WorkloadService
    private let autoPin: BundleAutoPin
    private let clock: Clock
    private static let tickSeconds: UInt64 = 5

    init(machines: MachineStore, commands: CommandStore, bundles: BundleStore, workloads: WorkloadService, autoPin: BundleAutoPin, clock: Clock) {
        self.machines = machines
        self.commands = commands
        self.bundles = bundles
        self.workloads = workloads
        self.autoPin = autoPin
        self.clock = clock
    }

    func start() {
        pinTheOnlyBuiltVersion()
        Task.detached { [self] in
            while !Task.isCancelled {
                await reconcile()
                try? await Task.sleep(nanoseconds: Self.tickSeconds * 1_000_000_000)
            }
        }
    }

    private func pinTheOnlyBuiltVersion() {
        do { try autoPin.run() } catch { RemoteLog.say("could not pin the built chat: \(error)") }
    }

    func reconcile() async {
        guard let pinned = try? bundles.pinned(), let list = try? machines.list(now: clock.now) else { return }
        for machine in list where machine.state != "offline" {
            for target in staleTargets(machine, pinned: pinned) where isDue(machine.id, target) {
                _ = try? await workloads.installBundle(actor: "root", machine: machine.id, workload: target)
            }
        }
    }

    /// Targets on this machine that have some bundle, but not the pinned one. `nil` means the machine itself.
    private func staleTargets(_ machine: MachineSummary, pinned: String) -> [String?] {
        let own: [String?] = machine.bundleVersion.map { $0 == pinned ? [] : [nil] } ?? []
        let inside: [String?] = machine.workloads.filter { $0.state == "running" && $0.bundleVersion != nil && $0.bundleVersion != pinned }.map { $0.id }
        return own + inside
    }

    /// Not while one is already going, not again at once after a failure, and never after the person turned the chat off.
    private func isDue(_ machine: String, _ workload: String?) -> Bool {
        guard let last = try? commands.lastBundleCommand(machine: machine, workloadId: workload) else { return true }
        guard let kind = BundleCommandKind(rawValue: last.type) else { return false }
        let finished = last.finishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        return BundleSchedule.isDue(last: BundleCommandFacts(kind: kind, state: last.state, finishedAt: finished), now: clock.now)
    }
}
