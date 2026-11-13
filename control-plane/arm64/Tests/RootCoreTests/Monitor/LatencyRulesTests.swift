import XCTest
@testable import RootCore

final class LatencySummaryTests: XCTestCase {
    private func sample(_ at: Int, _ millis: Int?) -> LatencySample {
        LatencySample(machineId: "a", at: at, millis: millis)
    }

    func testANormalListGivesAverageMaxAndLast() {
        let summary = LatencySummary.summarize([sample(10, 4), sample(20, 6), sample(30, 8)])
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.averageMs, 6)
        XCTAssertEqual(summary.maxMs, 8)
        XCTAssertEqual(summary.lastMs, 8)
        XCTAssertEqual(summary.percentFailed, 0)
    }

    func testFailedSamplesCountButAreLeftOutOfTheNumbers() {
        let summary = LatencySummary.summarize([sample(10, 4), sample(20, nil), sample(30, 10), sample(40, nil)])
        XCTAssertEqual(summary.count, 4)
        XCTAssertEqual(summary.failed, 2)
        XCTAssertEqual(summary.averageMs, 7)
        XCTAssertEqual(summary.maxMs, 10)
        XCTAssertEqual(summary.percentFailed, 50)
    }

    func testTheLastTimeIsTheNewestSampleEvenWhenItFailed() {
        let summary = LatencySummary.summarize([sample(20, 9), sample(30, nil)])
        XCTAssertNil(summary.lastMs)
        XCTAssertEqual(summary.averageMs, 9)
    }

    func testAnEmptyListGivesZerosAndNoAverages() {
        let summary = LatencySummary.summarize([])
        XCTAssertEqual(summary.count, 0)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertNil(summary.averageMs)
        XCTAssertNil(summary.maxMs)
        XCTAssertNil(summary.lastMs)
        XCTAssertEqual(summary.percentFailed, 0)
    }
}

final class LatencyBucketsTests: XCTestCase {
    private let start = 1_800_000_000

    func testTenSecondSamplesInOneMinuteBucketAverageTogether() {
        let samples = (0..<6).map { LatencySample(machineId: "a", at: start + $0 * 10, millis: $0 + 1) }
        let points = LatencyBuckets.points(samples, bucketSeconds: 60)
        XCTAssertEqual(points, [LatencyPoint(t: start, ms: 3.5)])
    }

    func testABucketWithOnlyFailuresIsNil() {
        let samples = [LatencySample(machineId: "a", at: start, millis: nil), LatencySample(machineId: "a", at: start + 10, millis: nil),
                       LatencySample(machineId: "a", at: start + 60, millis: 4)]
        let points = LatencyBuckets.points(samples, bucketSeconds: 60)
        XCTAssertEqual(points, [LatencyPoint(t: start, ms: nil), LatencyPoint(t: start + 60, ms: 4)])
    }

    func testMoreBucketsThanTheLimitKeepTheNewest() {
        let samples = (0..<5).map { LatencySample(machineId: "a", at: start + $0 * 60, millis: 1) }
        let points = LatencyBuckets.points(samples, bucketSeconds: 60, maxPoints: 3)
        XCTAssertEqual(points.map(\.t), [start + 120, start + 180, start + 240])
    }
}

final class LatencyRangeTests: XCTestCase {
    func testAMissingRangeIsTheLastHour() throws {
        XCTAssertEqual(try LatencyRange.parse(values: []), .hour)
    }

    func testTheThreeRangesAreAccepted() throws {
        XCTAssertEqual(try LatencyRange.parse(values: ["1h"]), .hour)
        XCTAssertEqual(try LatencyRange.parse(values: ["24h"]), .day)
        XCTAssertEqual(try LatencyRange.parse(values: ["7d"]), .week)
    }

    func testAnyOtherRangeIsRefused() {
        XCTAssertThrowsError(try LatencyRange.parse(values: ["2h"]))
        XCTAssertThrowsError(try LatencyRange.parse(values: ["1h", "1h"]))
    }

    func testTheWeekRangeLooksBackSevenDaysInTenMinuteBuckets() {
        XCTAssertEqual(LatencyRange.week.windowSeconds, 7 * 86_400)
        XCTAssertEqual(LatencyRange.week.bucketSeconds, 600)
    }
}
