import Foundation
import MSCore
import RootCore
import RootStore

/// Reads a machine's helper for the monitor. The shared reading keeps the helper from being asked more than once per few seconds.
final class StatsService: Sendable {
    static let helperTimeoutSeconds: TimeInterval = 5
    private static let missingRouteStatus = 404

    private let machines: MachineStore
    private let client: AgentClient
    private let clock: Clock
    private let readings: SharedReadings<MachineStats>

    init(machines: MachineStore, client: AgentClient, clock: Clock) {
        self.machines = machines
        self.client = client
        self.clock = clock
        readings = SharedReadings(clock: clock)
    }

    /// The envelope for one machine. Throws `MachineError.notFound` for a machine that does not exist.
    /// `processes` false: the answer has an empty process list, and a helper that has to be asked is asked not to scan them.
    func reply(for id: String, processes: Bool = true) async throws -> StatsReply<MachineStats> {
        let summary = try machines.get(id: id, now: clock.now)
        let offline = summary.state == "offline"
        let reading = offline ? await readings.lastKnown(id) : await readings.read(id, detailed: processes) { await self.fetch(id, processes: processes) }
        return StatsReply.make(machineOffline: offline, lastSeen: summary.lastSeen, reading: processes ? reading : reading.withoutProcesses())
    }

    /// A good reading without the process list and when it was taken, for the history sampler. Nil when the helper did not answer well (the sampler leaves a gap).
    func freshReading(for id: String) async -> (stats: MachineStats, at: Date)? {
        let reading = await readings.read(id, detailed: false, keepsAlive: false) { await self.fetch(id, processes: false) }
        guard reading.answer == .fresh, let value = reading.value, let at = reading.fetchedAt else { return nil }
        return (value, at)
    }

    private func fetch(_ id: String, processes: Bool) async -> ReadingOutcome<MachineStats> {
        let path = StatsQuery.helperPath(processes: processes)
        guard let reply = try? await client.call(machine: id, method: "GET", path: path, timeout: Self.helperTimeoutSeconds) else { return .unreachable }
        guard reply.status != Self.missingRouteStatus else { return .oldHelper }
        guard reply.status == 200, let stats = try? MachineStats.parse(reply.data) else { return .unreachable }
        return .fresh(stats)
    }
}
