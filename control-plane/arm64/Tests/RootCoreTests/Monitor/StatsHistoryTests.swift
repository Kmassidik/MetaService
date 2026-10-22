import XCTest
import MSCore
@testable import RootCore

private final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private func stats(cpu: Double? = 10, measuring: Bool = false) -> MachineStats {
    MachineStats(takenAt: "2026-10-21T10:00:00Z", measuring: measuring, uptimeSeconds: 1,
                 cpu: .init(coreCount: 2, totalPercent: cpu, coresPercent: nil, load: .init(one: 1, five: 2, fifteen: 3)),
                 memory: .init(totalBytes: 100, usedBytes: 40, cachedBytes: 20, freeBytes: 40, swapTotalBytes: 10, swapUsedBytes: 1), disks: [],
                 network: .init(receivedTotalBytes: 1, sentTotalBytes: 2, receivedBytesPerSecond: 30, sentBytesPerSecond: nil), processes: [])
}

private func point(_ t: Int, cpu: Double = 1) -> HistoryPoint {
    HistoryPoint(stats: stats(cpu: cpu), at: Date(timeIntervalSince1970: Double(t)))!
}

final class HistoryPointTests: XCTestCase {
    func testAReadingBecomesAPointWithTheNumbersTheChartsDraw() {
        let made = HistoryPoint(stats: stats(), at: Date(timeIntervalSince1970: 1_800_000_000))!
        XCTAssertEqual(made.t, 1_800_000_000)
        XCTAssertEqual([made.cpuPercent, made.netInBps], [10, 30])
        XCTAssertEqual(made.load, [1, 2, 3])
        XCTAssertEqual([made.memUsed, made.memCached, made.memTotal, made.swapUsed, made.swapTotal], [40, 20, 100, 1, 10])
        XCTAssertNil(made.netOutBps)
        XCTAssertNil(made.diskRead)
        XCTAssertNil(made.netDrops)
    }

    func testAReadingStillMeasuringMakesNoPoint() {
        XCTAssertNil(HistoryPoint(stats: stats(cpu: nil, measuring: true), at: Date()))
    }

    func testTheJsonUsesTheContractsNamesAndNullForAnUnknownNetworkSpeed() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let text = String(decoding: try encoder.encode(point(5)), as: UTF8.self)
        for key in ["\"t\":5", "\"cpu_percent\"", "\"mem_used\"", "\"mem_cached\"", "\"mem_total\"", "\"swap_used\"", "\"swap_total\"", "\"net_in_bps\"", "\"net_out_bps\":null", "\"load\":[1,2,3]"] {
            XCTAssertTrue(text.contains(key), "\(key) in \(text)")
        }
        for key in ["disk_read", "disk_write", "net_drops", "processes_count", "cpu_breakdown"] {
            XCTAssertFalse(text.contains(key), "\(key) is left out when unknown")
        }
    }

    func testDropsInAndOutAreAddedAndLoadNeedsAllThree() {
        var reading = stats()
        reading.network.dropsInTotal = 3
        reading.network.dropsOutTotal = 4
        reading.cpu.load = .init(one: 1, five: nil, fifteen: 3)
        let made = HistoryPoint(stats: reading, at: Date())!
        XCTAssertEqual(made.netDrops, 7)
        XCTAssertNil(made.load)
    }
}

final class StatsHistoryTests: XCTestCase {
    func testPointsComeBackOldestFirstAndAnHourIsThreeHundredSixty() {
        var history = StatsHistory()
        for t in 1...400 { history.record("mini", point(t)) }
        let all = history.points("mini", last: 360)
        XCTAssertEqual(all.count, 360)
        XCTAssertEqual(all.first?.t, 41)
        XCTAssertEqual(all.last?.t, 400)
        XCTAssertEqual(history.points("mini", last: 3).map(\.t), [398, 399, 400])
        XCTAssertEqual(StatsHistory.capacity, 360)
        XCTAssertEqual(StatsHistory.intervalSeconds, 10)
    }

    func testAPointNotNewerThanTheLastIsNotCountedTwice() {
        var history = StatsHistory()
        history.record("mini", point(10))
        history.record("mini", point(10, cpu: 99))
        history.record("mini", point(9))
        XCTAssertEqual(history.points("mini", last: 10).map(\.cpuPercent), [1])
    }

    func testMachinesBeyondTheLimitAreNotKept() {
        var history = StatsHistory(capacity: 5, maxMachines: 2)
        XCTAssertTrue(history.record("a", point(1)))
        XCTAssertTrue(history.record("b", point(1)))
        XCTAssertFalse(history.record("c", point(1)))
        XCTAssertTrue(history.record("a", point(2)), "a machine already kept keeps going")
        XCTAssertEqual(history.machineCount, 2)
        XCTAssertEqual(history.points("c", last: 5), [])
    }

    func testRemovedMachinesAreForgotten() {
        var history = StatsHistory()
        history.record("a", point(1))
        history.record("b", point(1))
        history.keepOnly(["a"])
        XCTAssertEqual(history.machineCount, 1)
        XCTAssertEqual(history.points("b", last: 5), [])
    }

    func testAskingForNothingOrForAMachineWeNeverSawGivesEmpty() {
        let history = StatsHistory()
        XCTAssertEqual(history.points("nobody", last: 360), [])
        XCTAssertEqual(history.points("nobody", last: 0), [])
    }
}

final class HistoryScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testEveryMachineIsDueOnceAnIntervalAndNotAllInTheSameSecond() {
        var schedule = HistorySchedule(intervalSeconds: 10)
        let names = (0..<40).map { "machine-\($0)" }
        var firstSecond: [String: Int] = [:]
        for second in 0..<11 {
            for id in schedule.due(online: names, now: start.addingTimeInterval(Double(second))) where firstSecond[id] == nil { firstSecond[id] = second }
        }
        XCTAssertEqual(firstSecond.count, 40, "every machine starts within the first interval")
        XCTAssertGreaterThan(Set(firstSecond.values).count, 3, "the starts are spread over the interval")
    }

    func testAMachineIsDueAgainOneIntervalLater() {
        var schedule = HistorySchedule(intervalSeconds: 10)
        var times: [Int] = []
        for second in 0..<60 where !schedule.due(online: ["mini"], now: start.addingTimeInterval(Double(second))).isEmpty { times.append(second) }
        XCTAssertTrue((5...6).contains(times.count), "about one per ten seconds: \(times)")
        XCTAssertEqual(Set(zip(times.dropFirst(), times).map { $0 - $1 }), [10])
    }

    func testTheDelayIsTheSameForTheSameNameAndNeverMoreThanAnInterval() {
        XCTAssertEqual(HistorySchedule.startDelay("mini", within: 10), HistorySchedule.startDelay("mini", within: 10))
        for name in ["a", "mini", "dgx-spark", "é"] { XCTAssertTrue((0..<10).contains(HistorySchedule.startDelay(name, within: 10))) }
    }

    func testAMachineThatLeftTheListStartsOverWhenItComesBack() {
        var schedule = HistorySchedule(intervalSeconds: 10)
        _ = schedule.due(online: ["mini"], now: start)
        _ = schedule.due(online: [], now: start.addingTimeInterval(5))
        XCTAssertEqual(schedule.due(online: ["mini"], now: start.addingTimeInterval(1000)), [], "a fresh delay, not an old due time that fires at once")
    }

    func testAfterALongPauseThereIsOneReadingNotABurst() {
        var schedule = HistorySchedule(intervalSeconds: 10)
        _ = schedule.due(online: ["mini"], now: start)
        _ = schedule.due(online: ["mini"], now: start.addingTimeInterval(10))
        let late = start.addingTimeInterval(500)
        XCTAssertEqual(schedule.due(online: ["mini"], now: late), ["mini"])
        XCTAssertEqual(schedule.due(online: ["mini"], now: late.addingTimeInterval(1)), [])
    }
}

private final class FakeSource: HistorySource, @unchecked Sendable {
    private let lock = NSLock()
    private var all: [SampledMachine] = []
    private var readings: [String: MachineStats] = [:]
    private(set) var asked: [String] = []
    let clock: TestClock
    init(clock: TestClock) { self.clock = clock }

    func set(machines: [SampledMachine], readings: [String: MachineStats]) { lock.withLock { all = machines; self.readings = readings } }
    func machines() async -> [SampledMachine] { lock.withLock { all } }
    func reading(of id: String) async -> (stats: MachineStats, at: Date)? {
        lock.withLock {
            asked.append(id)
            return readings[id].map { ($0, clock.now) }
        }
    }
    var askedList: [String] { lock.withLock { asked } }
}

final class HistorySamplerTests: XCTestCase {
    private func run(_ sampler: HistorySampler, clock: TestClock, seconds: Int) async {
        for _ in 0..<seconds {
            await sampler.pass()
            clock.advance(1)
        }
    }

    func testAnOnlineMachineGetsAboutOnePointEveryTenSeconds() async {
        let clock = TestClock()
        let source = FakeSource(clock: clock)
        source.set(machines: [.init(id: "mini", online: true)], readings: ["mini": stats()])
        let sampler = HistorySampler(source: source, clock: clock)
        await run(sampler, clock: clock, seconds: 60)
        let count = await sampler.points("mini", last: 360).count
        XCTAssertTrue((5...6).contains(count), "points: \(count)")
        let times = await sampler.points("mini", last: 360).map(\.t)
        XCTAssertEqual(times, times.sorted())
    }

    func testAnOfflineMachineIsNotAskedAndKeepsItsLastHour() async {
        let clock = TestClock()
        let source = FakeSource(clock: clock)
        source.set(machines: [.init(id: "mini", online: true)], readings: ["mini": stats()])
        let sampler = HistorySampler(source: source, clock: clock)
        await run(sampler, clock: clock, seconds: 30)
        let before = await sampler.points("mini", last: 360).count
        let asked = source.askedList.count
        source.set(machines: [.init(id: "mini", online: false)], readings: ["mini": stats()])
        await run(sampler, clock: clock, seconds: 60)
        XCTAssertEqual(source.askedList.count, asked, "no helper call for an offline machine")
        let after = await sampler.points("mini", last: 360).count
        XCTAssertEqual(after, before)
        XCTAssertGreaterThan(after, 0)
    }

    func testAnAnswerThatFailedLeavesAGapNotAZero() async {
        let clock = TestClock()
        let source = FakeSource(clock: clock)
        source.set(machines: [.init(id: "mini", online: true)], readings: [:])
        let sampler = HistorySampler(source: source, clock: clock)
        await run(sampler, clock: clock, seconds: 30)
        let none = await sampler.points("mini", last: 360)
        XCTAssertEqual(none, [])
        XCTAssertFalse(source.askedList.isEmpty, "it did try")
    }

    func testAMachineRemovedFromTheListIsForgotten() async {
        let clock = TestClock()
        let source = FakeSource(clock: clock)
        source.set(machines: [.init(id: "mini", online: true)], readings: ["mini": stats()])
        let sampler = HistorySampler(source: source, clock: clock)
        await run(sampler, clock: clock, seconds: 15)
        source.set(machines: [], readings: [:])
        await sampler.pass()
        let held = await sampler.machineCount
        XCTAssertEqual(held, 0)
    }

    func testAMachineThatIsStillMeasuringGivesNoPointYet() async {
        let clock = TestClock()
        let source = FakeSource(clock: clock)
        source.set(machines: [.init(id: "mini", online: true)], readings: ["mini": stats(cpu: nil, measuring: true)])
        let sampler = HistorySampler(source: source, clock: clock)
        await run(sampler, clock: clock, seconds: 25)
        let measuring = await sampler.points("mini", last: 360)
        XCTAssertEqual(measuring, [])
    }
}

final class HistoryQueryTests: XCTestCase {
    func testNothingMeansAnHourAndPlainNumbersFromOneToThreeHundredSixtyAreKept() throws {
        XCTAssertEqual(try HistoryQuery.points(values: []), 360)
        XCTAssertEqual(try HistoryQuery.points(values: ["1"]), 1)
        XCTAssertEqual(try HistoryQuery.points(values: ["360"]), 360)
        XCTAssertEqual(try HistoryQuery.points(values: ["42"]), 42)
    }

    func testEverythingElseIsRefused() {
        for bad in ["", "0", "361", "-1", "+5", " 5", "05", "5.0", "1e2", "abc", "١٢", "9999999999999999999"] {
            XCTAssertThrowsError(try HistoryQuery.points(values: [bad]), "'\(bad)' must be refused")
        }
        XCTAssertThrowsError(try HistoryQuery.points(values: ["5", "6"]))
    }
}
