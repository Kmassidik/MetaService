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

    init(machines: MachineStore, store: LatencyStore, clock: Clock) {
        self.machines = machines
        self.store = store
        self.clock = clock
        prober = LatencyProber(machines: machines, store: store, connector: TcpLatencyConnector(), clock: clock)
    }

    /// Starts the one loop that probes every registered machine. It runs for as long as the parent does.
    func start() {
        let prober = self.prober
        Task.detached { await prober.run() }
    }

    /// The summary and chart points of one machine for a range. Throws `MachineError.notFound` for a machine that does not exist.
    func reply(for id: String, range: LatencyRange) throws -> LatencyReply {
        _ = try machines.get(id: id, now: clock.now)
        let since = Int(clock.now.timeIntervalSince1970) - range.windowSeconds
        return LatencyReply.make(range: range, samples: try store.samples(machineId: id, since: since))
    }
}
