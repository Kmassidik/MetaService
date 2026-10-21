import XCTest
@testable import AgentCore

private final class FakeSource: StatsSource {
    var snapshots: [StatsSnapshot] = []
    func read() throws -> StatsSnapshot { snapshots.removeFirst() }
}

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func snapshot(at seconds: Double = 0, cores: [CoreTicks] = [CoreTicks(busy: 0, total: 0), CoreTicks(busy: 0, total: 0)], received: UInt64 = 0, sent: UInt64 = 0,
                      processes: [RawProcess] = [], disks: [DiskReading] = []) -> StatsSnapshot {
    StatsSnapshot(takenAt: start.addingTimeInterval(seconds), uptimeSeconds: 100, cores: cores, load: [1, 2, 3],
                  memory: MemoryReading(totalBytes: 1000, usedBytes: 600, cachedBytes: 300, freeBytes: 100, swapTotalBytes: 0, swapUsedBytes: 0),
                  disks: disks, receivedTotalBytes: received, sentTotalBytes: sent, processes: processes)
}

private func process(_ pid: Int, name: String = "p", cpuNanos: UInt64 = 0, memory: UInt64 = 1) -> RawProcess {
    RawProcess(pid: pid, name: name, user: "kurnia", cpuNanoseconds: cpuNanos, memoryBytes: memory)
}

private func sampler(_ snapshots: [StatsSnapshot]) -> StatsSampler {
    let source = FakeSource()
    source.snapshots = snapshots
    return StatsSampler(source: source)
}

final class StatsSamplerTests: XCTestCase {
    func testFirstAnswerIsMeasuringWithNullsNotZeros() throws {
        let stats = try sampler([snapshot(processes: [process(1)])]).sample()
        XCTAssertTrue(stats.measuring)
        XCTAssertNil(stats.cpu.totalPercent)
        XCTAssertNil(stats.cpu.coresPercent)
        XCTAssertNil(stats.network.receivedBytesPerSecond)
        XCTAssertNil(stats.processes[0].cpuPercent)
        XCTAssertEqual(stats.cpu.coreCount, 2)
        XCTAssertEqual(stats.memory.totalBytes, 1000)
    }

    func testPercentagesBetweenTwoSamples() throws {
        let first = snapshot(cores: [CoreTicks(busy: 0, total: 0), CoreTicks(busy: 0, total: 0)], received: 1000, sent: 0, processes: [process(1, cpuNanos: 0)])
        let second = snapshot(at: 5, cores: [CoreTicks(busy: 50, total: 100), CoreTicks(busy: 100, total: 100)], received: 6000, sent: 500, processes: [process(1, cpuNanos: 2_500_000_000)])
        let sampler = sampler([first, second])
        _ = try sampler.sample()
        let stats = try sampler.sample()
        XCTAssertFalse(stats.measuring)
        XCTAssertEqual(stats.cpu.coresPercent, [50, 100])
        XCTAssertEqual(stats.cpu.totalPercent, 75)
        XCTAssertEqual(stats.network.receivedBytesPerSecond, 1000)
        XCTAssertEqual(stats.network.sentBytesPerSecond, 100)
        XCTAssertEqual(stats.processes[0].cpuPercent, 50)
    }

    func testPreviousSampleOlderThanSixtySecondsIsMeasuringAgain() throws {
        let sampler = sampler([snapshot(), snapshot(at: 61)])
        _ = try sampler.sample()
        XCTAssertTrue(try sampler.sample().measuring)
    }

    func testCounterGoingBackwardsIsNullNotNegative() throws {
        let sampler = sampler([snapshot(received: 9000, sent: 10), snapshot(at: 5, received: 100, sent: 60)])
        _ = try sampler.sample()
        let stats = try sampler.sample()
        XCTAssertNil(stats.network.receivedBytesPerSecond)
        XCTAssertEqual(stats.network.sentBytesPerSecond, 10)
    }

    func testTopFifteenSortedByCpuThenMemoryThenPid() throws {
        let before = (1...20).map { process($0) }
        let after = (1...20).map { process($0, cpuNanos: UInt64($0 % 3) * 1_000_000_000, memory: UInt64($0)) }
        let sampler = sampler([snapshot(processes: before), snapshot(at: 10, processes: after)])
        _ = try sampler.sample()
        let list = try sampler.sample().processes
        XCTAssertEqual(list.count, 15)
        XCTAssertEqual(list.first?.pid, 20)
        let keys = list.map { [$0.cpuPercent ?? 0, Double($0.memoryBytes)] }
        XCTAssertEqual(keys, keys.sorted { $0[0] != $1[0] ? $0[0] > $1[0] : $0[1] > $1[1] })
    }

    func testMeasuringSortsByMemory() throws {
        let stats = try sampler([snapshot(processes: [process(1, memory: 5), process(2, memory: 9)])]).sample()
        XCTAssertEqual(stats.processes.map(\.pid), [2, 1])
    }

    func testNamesAndUsersCutAtSixtyFourCharacters() throws {
        let long = String(repeating: "x", count: 200)
        let stats = try sampler([snapshot(processes: [RawProcess(pid: 1, name: long, user: long, cpuNanoseconds: 0, memoryBytes: 1)])]).sample()
        XCTAssertEqual(stats.processes[0].name.count, 64)
        XCTAssertEqual(stats.processes[0].user.count, 64)
    }

    func testDisksAreCappedAndCut() throws {
        let disks = (0..<30).map { _ in DiskReading(mount: String(repeating: "m", count: 300), name: String(repeating: "n", count: 100), fs: "apfs", totalBytes: 10, freeBytes: 4) }
        let stats = try sampler([snapshot(disks: disks)]).sample()
        XCTAssertEqual(stats.disks.count, 16)
        XCTAssertEqual(stats.disks[0].mount.count, 128)
        XCTAssertEqual(stats.disks[0].name.count, 64)
        XCTAssertEqual(stats.disks[0].usedBytes, 6)
    }

    func testSecretInACommandLineCannotAppearAndGpusAreLeftOut() throws {
        // The source has no command-line field at all: the only text a process carries is name and user.
        let stats = try sampler([snapshot(processes: [process(1, name: "ssh")])]).sample()
        let json = String(decoding: try StatsJson.encode(stats), as: UTF8.self)
        XCTAssertFalse(json.contains("gpus"))
        XCTAssertFalse(json.contains("cmdline"))
        XCTAssertTrue(json.contains("\"cores_percent\":null"))
        XCTAssertTrue(json.contains("\"cpu_percent\":null"))
        XCTAssertTrue(json.contains("\"taken_at\":\"2027-01-15T08:00:00Z\""))
    }

    func testMemoryNeverAddsUpToMoreThanTotal() throws {
        let memory = MemoryReading(totalBytes: 100, usedBytes: 80, cachedBytes: 50, freeBytes: 40, swapTotalBytes: 0, swapUsedBytes: 0)
        let stats = try sampler([StatsSnapshot(takenAt: start, uptimeSeconds: 1, cores: [CoreTicks(busy: 0, total: 0)], load: [nil, nil, nil], memory: memory, disks: [],
                                               receivedTotalBytes: 0, sentTotalBytes: 0, processes: [])]).sample()
        XCTAssertLessThanOrEqual(stats.memory.usedBytes + stats.memory.cachedBytes + stats.memory.freeBytes, 100)
        XCTAssertNil(stats.cpu.load.one)
    }
}
