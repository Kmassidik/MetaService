import XCTest
@testable import AgentCore

private final class ListSource: StatsSource {
    var snapshots: [StatsSnapshot]
    init(_ snapshots: [StatsSnapshot]) { self.snapshots = snapshots }
    func read(includeProcesses: Bool) throws -> StatsSnapshot { snapshots.removeFirst() }
}

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func snapshot(at seconds: Double = 0, cores: Int = 4, extras: StatsExtras = StatsExtras(), processes: [RawProcess] = []) -> StatsSnapshot {
    StatsSnapshot(takenAt: start.addingTimeInterval(seconds), uptimeSeconds: 1, cores: Array(repeating: CoreTicks(busy: 0, total: 0), count: cores), load: [nil, nil, nil],
                  memory: MemoryReading(totalBytes: 10, usedBytes: 5, cachedBytes: 3, freeBytes: 2, swapTotalBytes: 0, swapUsedBytes: 0), disks: [],
                  receivedTotalBytes: 0, sentTotalBytes: 0, processes: processes, extras: extras)
}

private func twoAnswers(_ first: StatsSnapshot, _ second: StatsSnapshot) throws -> (MachineStats, MachineStats) {
    let sampler = StatsSampler(source: ListSource([first, second]))
    return (try sampler.sample(), try sampler.sample())
}

private func json(_ stats: MachineStats) throws -> String { String(decoding: try StatsJson.encode(stats), as: UTF8.self) }

final class StatsExtrasTests: XCTestCase {
    func testWithoutOptionalNumbersTheJsonLeavesThemOutNotZero() throws {
        let text = try json(try twoAnswers(snapshot(), snapshot(at: 5)).1)
        for key in ["physical_cores", "core_of", "clusters", "breakdown", "disk_io", "errors_in_total", "threads", "frequency", "temperature"] {
            XCTAssertFalse(text.contains(key), "\(key) must be left out")
        }
    }

    func testBreakdownIsTheShareOfEachStateAndOnlyTheFourAMacGives() throws {
        let first = snapshot(extras: StatsExtras(cpuStates: CpuStateTicks(user: 100, system: 50, nice: 0, idle: 850)))
        let second = snapshot(at: 5, extras: StatsExtras(cpuStates: CpuStateTicks(user: 200, system: 100, nice: 50, idle: 1150)))
        let (measuring, ready) = try twoAnswers(first, second)
        XCTAssertNil(measuring.cpu.breakdown, "null while measuring: nothing to compare with")
        XCTAssertEqual(ready.cpu.breakdown, MachineStats.Breakdown(user: 20, system: 10, nice: 10, idle: 60))
        let text = try json(ready)
        XCTAssertTrue(text.contains("\"breakdown\":{"))
        XCTAssertFalse(text.contains("iowait") || text.contains("softirq") || text.contains("steal"))
    }

    func testNoTimePassedGivesNoBreakdown() throws {
        let ticks = CpuStateTicks(user: 1, system: 1, nice: 1, idle: 1)
        let (_, ready) = try twoAnswers(snapshot(extras: StatsExtras(cpuStates: ticks)), snapshot(at: 5, extras: StatsExtras(cpuStates: ticks)))
        XCTAssertNil(ready.cpu.breakdown)
    }

    func testTopologyGivesPhysicalCoresClustersAndOneCoreEach() throws {
        let topology = CpuTopology(physicalCores: 4, clusters: [CpuCluster(name: "Performance", logical: 2), CpuCluster(name: "Efficiency", logical: 2)])
        let stats = try twoAnswers(snapshot(extras: StatsExtras(topology: topology)), snapshot(at: 5)).0
        XCTAssertEqual(stats.cpu.physicalCores, 4)
        XCTAssertEqual(stats.cpu.coreOf, [0, 1, 2, 3])
        XCTAssertEqual(stats.cpu.clusters, [MachineStats.Cluster(name: "Performance", logical: 2), MachineStats.Cluster(name: "Efficiency", logical: 2)])
    }

    func testHyperThreadedCoresPairNeighboursAndAnUnevenCountIsLeftOut() {
        XCTAssertEqual(StatsMath.coreOf(logical: 8, physical: 4), [0, 0, 1, 1, 2, 2, 3, 3])
        XCTAssertNil(StatsMath.coreOf(logical: 7, physical: 4))
        XCTAssertNil(StatsMath.coreOf(logical: 4, physical: 8))
        XCTAssertNil(StatsMath.coreOf(logical: 4, physical: 0))
    }

    func testClustersAreLeftOutWhenTheSystemNamesNone() throws {
        let stats = try twoAnswers(snapshot(extras: StatsExtras(topology: CpuTopology(physicalCores: 4, clusters: []))), snapshot(at: 5)).0
        XCTAssertNil(stats.cpu.clusters)
        XCTAssertFalse(try json(stats).contains("clusters"))
    }

    func testDiskSpeedIsTheChangeOfTheTotalsAndNeedsTwoReadings() throws {
        let first = snapshot(extras: StatsExtras(diskTotals: DiskTotals(readBytes: 1000, writtenBytes: 5000)))
        let second = snapshot(at: 5, extras: StatsExtras(diskTotals: DiskTotals(readBytes: 6000, writtenBytes: 5500)))
        let (measuring, ready) = try twoAnswers(first, second)
        XCTAssertNil(measuring.diskIo)
        XCTAssertEqual(ready.diskIo, MachineStats.DiskIo(readBytesPerSecond: 1000, writeBytesPerSecond: 100))
        let text = try json(ready)
        XCTAssertTrue(text.contains("\"disk_io\":{") && text.contains("\"read_bytes_per_second\":1000") && text.contains("\"write_bytes_per_second\":100"))
    }

    func testDiskTotalsThatWentBackwardsGiveNoSpeed() throws {
        let first = snapshot(extras: StatsExtras(diskTotals: DiskTotals(readBytes: 9000, writtenBytes: 10)))
        let second = snapshot(at: 5, extras: StatsExtras(diskTotals: DiskTotals(readBytes: 100, writtenBytes: 60)))
        XCTAssertNil(try twoAnswers(first, second).1.diskIo)
    }

    func testNetworkErrorsAndDropsAreRunningTotalsAndThereIsNoDropOnTheWayOut() throws {
        let extras = StatsExtras(networkIssues: NetworkIssues(errorsIn: 3, errorsOut: 4, dropsIn: 5))
        let stats = try twoAnswers(snapshot(extras: extras), snapshot(at: 5)).0
        XCTAssertEqual([stats.network.errorsInTotal, stats.network.errorsOutTotal, stats.network.dropsInTotal], [3, 4, 5])
        let text = try json(stats)
        XCTAssertTrue(text.contains("\"errors_in_total\":3") && text.contains("\"drops_in_total\":5"))
        XCTAssertFalse(text.contains("drops_out"))
    }

    func testTheNumberOfRunningProgramsIsSentWhenKnownAndLeftOutWhenNot() throws {
        let known = try twoAnswers(snapshot(extras: StatsExtras(processCount: 412)), snapshot(at: 5)).0
        XCTAssertEqual(known.processCount, 412)
        XCTAssertTrue(try json(known).contains("\"process_count\":412"))
        XCTAssertFalse(try json(try twoAnswers(snapshot(), snapshot(at: 5)).0).contains("process_count"))
    }

    func testProcessThreadCountIsSentWhenKnown() throws {
        let listed = [RawProcess(pid: 1, name: "a", user: "u", cpuNanoseconds: 0, memoryBytes: 1, threads: 9), RawProcess(pid: 2, name: "b", user: "u", cpuNanoseconds: 0, memoryBytes: 0)]
        let stats = try twoAnswers(snapshot(processes: listed), snapshot(at: 5)).0
        XCTAssertEqual(stats.processes.map(\.threads), [9, nil])
    }
}
