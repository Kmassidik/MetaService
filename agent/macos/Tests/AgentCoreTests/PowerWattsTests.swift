import XCTest
@testable import AgentCore

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private final class ListSource: StatsSource {
    var snapshots: [StatsSnapshot]
    init(_ snapshots: [StatsSnapshot]) { self.snapshots = snapshots }
    func read(includeProcesses: Bool) throws -> StatsSnapshot { snapshots.removeFirst() }
}

private func snapshot(at seconds: Double = 0, extras: StatsExtras = StatsExtras()) -> StatsSnapshot {
    StatsSnapshot(takenAt: start.addingTimeInterval(seconds), uptimeSeconds: 1, cores: [], load: [nil, nil, nil],
                  memory: MemoryReading(totalBytes: 10, usedBytes: 5, cachedBytes: 3, freeBytes: 2, swapTotalBytes: 0, swapUsedBytes: 0), disks: [],
                  receivedTotalBytes: 0, sentTotalBytes: 0, processes: [], extras: extras)
}

private func stats(_ extras: StatsExtras) throws -> MachineStats {
    let first = snapshot(extras: extras)
    let sampler = StatsSampler(source: ListSource([first, snapshot(at: 5, extras: extras)]))
    _ = try sampler.sample()
    return try sampler.sample()
}

private func json(_ stats: MachineStats) throws -> String { String(decoding: try StatsJson.encode(stats), as: UTF8.self) }

final class PowerWattsTests: XCTestCase {
    func testPowerWattsIsEncodedOnlyWhenKnown() throws {
        let text = try json(try stats(StatsExtras(machinePowerWatts: 12.3)))
        XCTAssertTrue(text.contains("\"power_watts\":12.3"), text)
        let unknown = try json(try stats(StatsExtras()))
        XCTAssertFalse(unknown.contains("power_watts"), "unknown power must be left out, not null or zero: \(unknown)")
    }
}
