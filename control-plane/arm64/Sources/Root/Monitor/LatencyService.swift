import Foundation
import MSCore
import RootCore
import RootStore

/// Serves the latency of a machine from the stored samples, and starts the prober that fills them in.
final class LatencyService: Sendable {
    private let machines: MachineStore
    private let store: LatencyStore
    private let clock: Clock
    private let prober: LatencyProber

    init(machines: MachineStore, store: LatencyStore, client: AgentClient, clock: Clock) {
        self.machines = machines
        self.store = store
        self.clock = clock
        prober = LatencyProber(machines: machines, store: store, connector: AgentHealthConnector(client: client), clock: clock)
    }

    /// Starts the one loop that probes every registered machine. It runs for as long as the parent does.
    func start() {
        let prober = self.prober
        Task.detached { await prober.run() }
    }

    /// The summary and chart points of one machine for a range. The summary always covers the whole window.
    /// Throws `MachineError.notFound` for a machine that does not exist.
    func reply(for id: String, range: LatencyRange) throws -> LatencyReply {
        _ = try machines.get(id: id, now: clock.now)
        let since = Int(clock.now.timeIntervalSince1970) - range.windowSeconds
        let summary = try store.summary(machineId: id, since: since)
        let points = try chartPoints(for: id, range: range, since: since)
        return LatencyReply.make(range: range, summary: summary, points: points)
    }

    /// The hour is drawn from its raw samples; a day and a week from buckets the database makes over the whole window.
    private func chartPoints(for id: String, range: LatencyRange, since: Int) throws -> [LatencyPoint] {
        switch range {
        case .hour:
            return LatencyBuckets.points(try store.samples(machineId: id, since: since), bucketSeconds: range.bucketSeconds)
        case .day, .week:
            return try store.buckets(machineId: id, since: since, bucketSeconds: range.bucketSeconds, limit: LatencyTiming.maxPoints)
        }
    }
}
