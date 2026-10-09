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
    private let clock: Clock
    private static let tickSeconds: UInt64 = 5
    private static let retryAfter: TimeInterval = 300

    init(machines: MachineStore, commands: CommandStore, bundles: BundleStore, workloads: WorkloadService, clock: Clock) {
        self.machines = machines
        self.commands = commands
        self.bundles = bundles
        self.workloads = workloads
        self.clock = clock
    }

    func start() {
        Task.detached { [self] in
            while !Task.isCancelled {
                await reconcile()
                try? await Task.sleep(nanoseconds: Self.tickSeconds * 1_000_000_000)
            }
        }
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

    /// Not while one is already going, and not again at once after a failure.
    private func isDue(_ machine: String, _ workload: String?) -> Bool {
        guard let last = try? commands.lastBundleInstall(machine: machine, workloadId: workload) else { return true }
        guard last.state == "failed" else { return last.state == "succeeded" }
        guard let finished = last.finishedAt.flatMap({ ISO8601DateFormatter().date(from: $0) }) else { return false }
        return clock.now.timeIntervalSince(finished) > Self.retryAfter
    }
}
