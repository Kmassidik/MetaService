import XCTest
import MSCore
@testable import RootCore

/// The office clock is UTC+7. 2026-11-14 10:00 local is epoch 1_794_625_200.
private let localNoonEpoch = 1_794_625_200

final class NetUsageAccumulatorTests: XCTestCase {
    private var accumulator = NetMinuteAccumulator()

    override func setUp() {
        accumulator = NetMinuteAccumulator()
    }

    func testNetUsageEachReadingCountsItsSpeedTimesTenSeconds() {
        XCTAssertEqual(accumulator.add(machineId: "a", at: 60, inBps: 100, outBps: 50), [])
        XCTAssertEqual(accumulator.add(machineId: "a", at: 70, inBps: 200, outBps: nil), [])
        let finished = accumulator.add(machineId: "a", at: 120, inBps: 1, outBps: 1)
        XCTAssertEqual(finished, [NetMinute(machineId: "a", minute: 1, inBytes: 3_000, outBytes: 500, inPeakBps: 200, outPeakBps: 50, samples: 2)])
    }

    func testNetUsagePeakIsTheHighestSpeedOfTheMinute() {
        _ = accumulator.add(machineId: "a", at: 60, inBps: 10, outBps: 900)
        _ = accumulator.add(machineId: "a", at: 70, inBps: 300, outBps: 20)
        _ = accumulator.add(machineId: "a", at: 80, inBps: 20, outBps: 30)
        let minute = accumulator.takeOpenMinutes().first
        XCTAssertEqual([minute?.inPeakBps, minute?.outPeakBps], [300, 900])
    }

    func testNetUsageNilSpeedCountsAsZeroBytesAndNoSample() {
        _ = accumulator.add(machineId: "a", at: 60, inBps: nil, outBps: nil)
        _ = accumulator.add(machineId: "a", at: 70, inBps: 5, outBps: nil)
        let minute = accumulator.takeOpenMinutes().first
        XCTAssertEqual(minute, NetMinute(machineId: "a", minute: 1, inBytes: 50, outBytes: 0, inPeakBps: 5, outPeakBps: 0, samples: 1))
    }

    func testNetUsageTheMinuteRollsOverAndTheFinishedMinuteComesBack() {
        _ = accumulator.add(machineId: "a", at: 118, inBps: 7, outBps: 7)
        let finished = accumulator.add(machineId: "a", at: 180, inBps: 1, outBps: 1)
        XCTAssertEqual(finished.map(\.minute), [1])
        XCTAssertEqual(accumulator.takeOpenMinutes().map(\.minute), [3])
    }

    func testNetUsageTwoMachinesDoNotMix() {
        _ = accumulator.add(machineId: "a", at: 60, inBps: 100, outBps: nil)
        _ = accumulator.add(machineId: "b", at: 61, inBps: 1, outBps: 2)
        _ = accumulator.add(machineId: "a", at: 70, inBps: 100, outBps: nil)
        let minutes = accumulator.takeOpenMinutes().sorted { $0.machineId < $1.machineId }
        XCTAssertEqual(minutes.map(\.machineId), ["a", "b"])
        XCTAssertEqual(minutes.map(\.inBytes), [2_000, 10])
        XCTAssertEqual(minutes.map(\.outBytes), [0, 20])
    }

    func testNetUsageAReadingNotNewerThanTheLastIsIgnored() {
        _ = accumulator.add(machineId: "a", at: 60, inBps: 100, outBps: nil)
        _ = accumulator.add(machineId: "a", at: 60, inBps: 100, outBps: nil)
        XCTAssertEqual(accumulator.takeOpenMinutes().first?.samples, 1)
    }

    func testNetUsageAFlushedMinuteContinuesAsAPartThatAddsUp() {
        _ = accumulator.add(machineId: "a", at: 60, inBps: 100, outBps: nil)
        let firstPart = accumulator.takeOpenMinutes()
        _ = accumulator.add(machineId: "a", at: 70, inBps: 100, outBps: nil)
        XCTAssertEqual(firstPart.map(\.inBytes), [1_000])
        XCTAssertEqual(accumulator.takeOpenMinutes().map(\.inBytes), [1_000])
    }
}

final class NetUsageRangeTests: XCTestCase {
    private let clock = FixedClock(Date(timeIntervalSince1970: TimeInterval(localNoonEpoch)))

    private var now: Int { Int(clock.now.timeIntervalSince1970) }

    func testNetUsageTodayStartsAtLocalMidnight() {
        XCTAssertEqual(NetUsageRange.today.start(now: now), 1_794_589_200)
    }

    func testNetUsageAtExactlyMidnightTodayIsThatMidnight() {
        XCTAssertEqual(NetUsageRange.today.start(now: 1_794_589_200), 1_794_589_200)
    }

    func testNetUsageMonthStartsOnTheFirstAtLocalMidnight() {
        XCTAssertEqual(NetUsageRange.month.start(now: now), 1_793_466_000)
    }

    func testNetUsageThirtyDaysIsTheLast30x24Hours() {
        XCTAssertEqual(NetUsageRange.thirtyDays.start(now: now), localNoonEpoch - 30 * 86_400)
    }

    func testNetUsageRangeDefaultsToTodayAndRefusesOtherTexts() throws {
        XCTAssertEqual(try NetUsageRange.parse(values: []), .today)
        XCTAssertEqual(try NetUsageRange.parse(values: ["30d"]), .thirtyDays)
        XCTAssertThrowsError(try NetUsageRange.parse(values: ["7d"]))
        XCTAssertThrowsError(try NetUsageRange.parse(values: ["month", "today"]))
    }

    func testNetUsageDaysDefaultsToSevenAndAcceptsOnlySevenOrThirty() throws {
        XCTAssertEqual(try NetUsageDays.parse(values: []), .week)
        XCTAssertEqual(try NetUsageDays.parse(values: ["30"]), .month)
        XCTAssertThrowsError(try NetUsageDays.parse(values: ["14"]))
        XCTAssertThrowsError(try NetUsageDays.parse(values: ["7d"]))
    }

    func testNetUsageSummaryAddsBytesButNotPeaks() {
        let total = NetUsageSummary.summarize([
            NetUsageFigures(inBytes: 10, outBytes: 1, inPeakBps: 900, outPeakBps: 5),
            NetUsageFigures(inBytes: 5, outBytes: 2, inPeakBps: 3, outPeakBps: 7),
        ])
        XCTAssertEqual(total, NetUsageSummary(inBytes: 15, outBytes: 3))
        XCTAssertEqual(NetUsageSummary.summarize([]), NetUsageSummary(inBytes: 0, outBytes: 0))
    }
}
