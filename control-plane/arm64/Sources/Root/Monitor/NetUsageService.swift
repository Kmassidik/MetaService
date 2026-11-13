import Foundation
import MSCore
import RootCore
import RootStore

/// Serves the network usage of the machines from the stored minutes, and owns the collector that writes them.
final class NetUsageService: Sendable {
    private let machines: MachineStore
    private let store: NetMinuteStore
    private let clock: Clock
    let collector: NetUsageCollector

    init(machines: MachineStore, store: NetMinuteStore, clock: Clock) {
        self.machines = machines
        self.store = store
        self.clock = clock
        collector = NetUsageCollector(store: store, clock: clock)
    }

    /// Starts the collector's flush loop. It runs for as long as the parent does.
    func start() {
        let collector = self.collector
        Task.detached { await collector.run() }
    }

    /// The usage of every registered machine for a range (zeros when a machine has no data), and the total of them.
    func usageReply(range: NetUsageRange) throws -> NetUsageReply {
        let now = Int(clock.now.timeIntervalSince1970)
        let since = range.start(now: now)
        let listed = try machines.list(now: clock.now)
        let figures = try listed.map { try store.usage(machineId: $0.id, since: since, until: now) }
        let rows = zip(listed, figures).map { NetUsageMachine(machineId: $0.id, name: $0.name, figures: $1) }
        return NetUsageReply(range: range.rawValue, since: since, machines: rows, total: NetUsageSummary.summarize(figures))
    }

    /// Traffic per local day over all machines, for the last `days` days including today, oldest first.
    func dailyReply(days: NetUsageDays) throws -> NetUsageDailyReply {
        let now = Int(clock.now.timeIntervalSince1970)
        let firstDay = NetUsageRange.today.start(now: now) - (days.rawValue - 1) * NetUsageRules.secondsPerDay
        let rows = try store.dailyTotals(machineId: nil, sinceMinute: firstDay / NetUsageRules.secondsPerMinute,
                                         untilMinute: now / NetUsageRules.secondsPerMinute + 1,
                                         offsetMinutes: NetUsageRules.officeUtcOffsetMinutes)
        return NetUsageDailyReply(days: rows)
    }
}
