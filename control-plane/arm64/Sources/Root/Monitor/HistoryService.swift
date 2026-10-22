import Foundation
import MSCore
import RootCore
import RootStore

/// The last hour of readings per machine, in memory. It asks the machines through the same shared reading as the stats route, so a person watching and the sampler together
/// still cost a helper at most one call per four seconds.
final class HistoryService: Sendable {
    private let machines: MachineStore
    private let clock: Clock
    private let intervalSeconds: Int
    private let sampler: HistorySampler

    init(machines: MachineStore, stats: StatsService, clock: Clock, intervalSeconds: Int) {
        self.machines = machines
        self.clock = clock
        self.intervalSeconds = intervalSeconds
        sampler = HistorySampler(source: ServiceSource(machines: machines, stats: stats, clock: clock), clock: clock, intervalSeconds: intervalSeconds)
    }

    /// Starts the one loop that samples every online machine. It runs for as long as the parent does.
    func start() {
        let sampler = self.sampler
        Task.detached { await sampler.run() }
    }

    /// The newest `count` points of one machine. Throws `MachineError.notFound` for a machine that does not exist.
    func reply(for id: String, points count: Int) async throws -> HistoryReply {
        _ = try machines.get(id: id, now: clock.now)
        return HistoryReply(intervalSeconds: intervalSeconds, points: await sampler.points(id, last: count))
    }
}

private struct ServiceSource: HistorySource {
    let machines: MachineStore
    let stats: StatsService
    let clock: Clock

    func machines() async -> [SampledMachine] {
        let all = (try? machines.list(now: clock.now)) ?? []
        return all.map { SampledMachine(id: $0.id, online: $0.state == "online") }
    }

    func reading(of id: String) async -> (stats: MachineStats, at: Date)? {
        await stats.freshReading(for: id)
    }
}
