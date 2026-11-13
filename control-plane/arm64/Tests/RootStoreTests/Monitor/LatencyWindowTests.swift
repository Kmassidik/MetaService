import XCTest
import RootCore
@testable import RootStore

/// The 24h and 7d views must cover the whole window: the summary counts every row, and the charts keep every bucket that has data.
final class LatencyWindowTests: XCTestCase {
    private let now = 1_800_000_000
    private let weekSeconds = 7 * 86_400
    private let hourSeconds = 3_600
    private let recentIntervalSeconds = 10
    private let olderIntervalSeconds = 600
    private let chartCap = 1_000
    private let knownMillis = 5
    private var store: LatencyStore!
    private var insertedUp = 0

    override func setUpWithError() throws {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = LatencyStore(database)
        try fillMachineUp()
        try fillMachineDown()
    }

    /// "up": one probe every 10 s for the last hour, then one every 10 minutes for the rest of the 7 days. Some probes fail on purpose.
    private func fillMachineUp() throws {
        let since = now - weekSeconds
        let recent = (0..<(hourSeconds / recentIntervalSeconds)).map { index in
            LatencySample(machineId: "up", at: now - hourSeconds + index * recentIntervalSeconds, millis: index % 10 == 4 ? nil : knownMillis)
        }
        let older = (0..<((weekSeconds - hourSeconds) / olderIntervalSeconds)).map { index in
            LatencySample(machineId: "up", at: since + index * olderIntervalSeconds, millis: index % 5 == 0 ? nil : 8)
        }
        insertedUp = recent.count + older.count
        try store.record(older + recent)
    }

    /// "down": every probe for the last hour failed.
    private func fillMachineDown() throws {
        let failed = (0..<(hourSeconds / recentIntervalSeconds)).map { index in
            LatencySample(machineId: "down", at: now - hourSeconds + index * recentIntervalSeconds, millis: nil)
        }
        try store.record(failed)
    }

    func testTheSevenDaySummaryCountsEveryInsertedRow() throws {
        let summary = try store.summary(machineId: "up", since: now - weekSeconds)
        let expectedFailed = (0..<((weekSeconds - hourSeconds) / olderIntervalSeconds)).filter { $0 % 5 == 0 }.count
            + (0..<(hourSeconds / recentIntervalSeconds)).filter { $0 % 10 == 4 }.count
        XCTAssertEqual(summary.count, insertedUp)
        XCTAssertEqual(summary.failed, expectedFailed)
        XCTAssertEqual(summary.maxMs, 8)
        XCTAssertEqual(summary.lastMs, knownMillis)
    }

    func testTheSevenDayBucketsStayUnderTheCapAndStartAtTheWindow() throws {
        let since = now - weekSeconds
        let bucketSeconds = LatencyRange.week.bucketSeconds
        let points = try store.buckets(machineId: "up", since: since, bucketSeconds: bucketSeconds, limit: chartCap)
        XCTAssertLessThanOrEqual(points.count, chartCap)
        XCTAssertFalse(points.isEmpty)
        XCTAssertLessThanOrEqual(abs(points[0].t - since), bucketSeconds)
        XCTAssertEqual(points.map(\.t), points.map(\.t).sorted(), "oldest first")
    }

    func testTheDayBucketsStayUnderTheCapAndStartAtTheWindow() throws {
        let since = now - 86_400
        let bucketSeconds = LatencyRange.day.bucketSeconds
        let points = try store.buckets(machineId: "up", since: since, bucketSeconds: bucketSeconds, limit: chartCap)
        XCTAssertLessThanOrEqual(points.count, chartCap)
        XCTAssertFalse(points.isEmpty)
        XCTAssertLessThanOrEqual(abs(points[0].t - since), bucketSeconds)
    }

    func testABucketOfOnlyFailedProbesIsNil() throws {
        let points = try store.buckets(machineId: "down", since: now - hourSeconds, bucketSeconds: LatencyRange.day.bucketSeconds, limit: chartCap)
        XCTAssertFalse(points.isEmpty)
        XCTAssertTrue(points.allSatisfy { $0.ms == nil })
    }

    func testTheLastTimeIsNilWhenTheNewestProbeFailed() throws {
        XCTAssertNil(try store.lastMillis(machineId: "down"))
        XCTAssertEqual(try store.lastMillis(machineId: "up"), knownMillis)
        XCTAssertNil(try store.lastMillis(machineId: "nobody"))
    }
}
