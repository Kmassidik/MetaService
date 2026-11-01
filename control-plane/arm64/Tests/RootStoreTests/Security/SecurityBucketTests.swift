import XCTest
import RootCore
@testable import RootStore

/// The ten-minute failed-login buckets: the short ranges' data (1 h to 24 h).
final class SecurityBucketTests: XCTestCase {
    private var database: Database!
    private var store: SecurityStore!
    private let now = Date(timeIntervalSince1970: 1_793_523_000) // 2026-11-01T08:50:00Z

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.run(SecurityDatabase.steps, on: database)
        store = SecurityStore(database)
    }

    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private func failed(at time: Date, user: String? = "root", address: String? = "45.1.1.1", count: Int = 1) -> SecurityHelperEvent {
        SecurityHelperEvent(time: time, type: .failedLogin, user: user, address: address, method: nil, count: count, until: nil, detail: nil)
    }

    private func pull(_ events: [SecurityHelperEvent], cursor: String = "c1") -> SecurityPull {
        SecurityPull(cursor: cursor, reset: false, events: events, baseline: .unknown, received: events.count, dropped: 0)
    }

    private func count(_ table: String) throws -> Int {
        let rows = table == "failed_buckets"
            ? try database.query("SELECT COALESCE(SUM(count), 0) AS n FROM failed_buckets")
            : try database.query("SELECT COALESCE(SUM(count), 0) AS n FROM failed_daily")
        return rows.first?.int("n") ?? -1
    }

    func testBucketStartsAtTheTenMinuteBoundary() {
        XCTAssertEqual(SecurityTime.bucketStart(SecurityTime.parse("2026-11-01T08:40:00Z")!), "2026-11-01T08:40:00Z")
        XCTAssertEqual(SecurityTime.bucketStart(SecurityTime.parse("2026-11-01T08:49:59Z")!), "2026-11-01T08:40:00Z")
        XCTAssertEqual(SecurityTime.bucketStart(SecurityTime.parse("2026-11-01T08:50:00Z")!), "2026-11-01T08:50:00Z")
        XCTAssertEqual(SecurityTime.bucketStart(SecurityTime.parse("2026-10-31T23:59:59Z")!), "2026-10-31T23:50:00Z")
        XCTAssertEqual(SecurityTime.bucketStart(SecurityTime.parse("2026-11-01T00:00:00Z")!), "2026-11-01T00:00:00Z")
    }

    func testBucketStartAfterLeavesOutABucketThatBeganAtTheMoment() {
        XCTAssertEqual(SecurityTime.bucketStartAfter(SecurityTime.parse("2026-11-01T07:50:00Z")!), "2026-11-01T08:00:00Z")
        XCTAssertEqual(SecurityTime.bucketStartAfter(SecurityTime.parse("2026-11-01T07:55:00Z")!), "2026-11-01T08:00:00Z")
    }

    func testRangesUpToADayUseBucketsAndLongerOnesUseDays() {
        XCTAssertEqual(SecurityRange.allCases.filter(\.usesBuckets), [.hour, .sixHours, .twelveHours, .day])
        XCTAssertEqual(SecurityRange.hour.window(now: now), .buckets(from: "2026-11-01T08:00:00Z"))
        XCTAssertEqual(SecurityRange.day.window(now: now), .buckets(from: "2026-10-31T09:00:00Z"))
        XCTAssertEqual(SecurityRange.week.window(now: now), .days(from: "2026-10-25"))
    }

    func testEveryFailedLoginIsWrittenToBothTablesTogether() throws {
        try store.store(pull([failed(at: ago(100), count: 3), failed(at: ago(50), count: 2)]), machine: "a", now: now)
        XCTAssertEqual(try count("failed_daily"), 5)
        XCTAssertEqual(try count("failed_buckets"), 5)
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM failed_buckets").first?.int("n"), 1)
    }

    func testAnUnknownUserAndAddressMergeInOneBucketRow() throws {
        try store.store(pull([failed(at: ago(20), user: nil, address: nil), failed(at: ago(10), user: nil, address: nil, count: 2)]), machine: "a", now: now)
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM failed_buckets").first?.int("n"), 1)
        XCTAssertEqual(try count("failed_buckets"), 3)
    }

    func testEventsInDifferentBucketsStaySeparateAndBucketsFollowTheRange() throws {
        try store.store(pull([failed(at: ago(5 * 60), count: 4), failed(at: ago(25 * 60), count: 1), failed(at: ago(3 * 3_600), count: 7), failed(at: ago(20 * 3_600), count: 9)]), machine: "a", now: now)
        XCTAssertEqual(try store.buckets(from: "2026-11-01T08:00:00Z").map(\.failed), [1, 4])
        XCTAssertEqual(try store.failedTotals(in: SecurityRange.hour.window(now: now)), ["a": 5])
        XCTAssertEqual(try store.failedTotals(in: SecurityRange.sixHours.window(now: now)), ["a": 12])
        XCTAssertEqual(try store.failedTotals(in: SecurityRange.day.window(now: now)), ["a": 21])
        XCTAssertEqual(try store.buckets(from: SecurityTime.bucketStartAfter(SecurityRange.hour.start(now: now))).map(\.start), ["2026-11-01T08:20:00Z", "2026-11-01T08:40:00Z"])
        XCTAssertEqual(try store.topUsers(in: SecurityRange.hour.window(now: now)), [SecurityTopRow(name: "root", count: 5)])
        XCTAssertEqual(try store.topAddresses(in: SecurityRange.sixHours.window(now: now)).first, SecurityTopRow(name: "45.1.1.1", count: 12))
    }

    func testAnOneHourRangeHoldsAtMostSixBucketsPerMachine() throws {
        let events = (0..<12).map { failed(at: ago(Double($0) * 600 + 1)) }
        try store.store(pull(events), machine: "a", now: now)
        let first = SecurityTime.bucketStartAfter(SecurityRange.hour.start(now: now))
        XCTAssertLessThanOrEqual(try store.buckets(from: first).count, 6)
    }

    func testAZeroBucketHasNoRow() throws {
        try store.store(pull([failed(at: ago(5 * 60))]), machine: "a", now: now)
        XCTAssertEqual(try store.buckets(from: "2026-10-31T09:00:00Z").count, 1)
        XCTAssertTrue(try store.buckets(from: "2026-11-01T08:50:00Z").isEmpty)
    }

    func testReplayingACatchUpAddsToTheBucketOfTheLatestTime() throws {
        try store.store(pull([failed(at: ago(7_200), count: 50)], cursor: "c1"), machine: "a", now: now)
        try store.store(pull([failed(at: ago(7_200), count: 5)], cursor: "c2"), machine: "a", now: now)
        XCTAssertEqual(try count("failed_buckets"), 55)
        XCTAssertEqual(try store.cursor(machine: "a"), "c2")
    }

    func testBucketsOlderThanEightDaysAreNotStoredAndPruneDeletesThem() throws {
        try store.store(pull([failed(at: ago(9 * 86_400), count: 6), failed(at: ago(60))]), machine: "a", now: now)
        XCTAssertEqual(try count("failed_buckets"), 1)
        XCTAssertEqual(try count("failed_daily"), 7)
        try database.execute("INSERT INTO failed_buckets (bucket_start, machine, count, last_seen) VALUES (?, 'a', 3, ?)", [.text(SecurityTime.text(ago(8 * 86_400 + 700))), .text(SecurityTime.text(ago(8 * 86_400 + 700)))])
        try database.execute("INSERT INTO failed_buckets (bucket_start, machine, count, last_seen) VALUES (?, 'a', 2, ?)", [.text(SecurityTime.text(ago(7 * 86_400))), .text(SecurityTime.text(ago(7 * 86_400)))])
        try store.prune(now: now)
        XCTAssertEqual(try count("failed_buckets"), 3)
        XCTAssertEqual(try count("failed_daily"), 7)
    }

    func testTheLogOfAShortRangeListsTheBucketRowsNewestFirst() throws {
        try store.store(pull([failed(at: ago(300), user: "root", count: 4), failed(at: ago(7_200), user: "admin", count: 2)]), machine: "a", now: now)
        var query = SecurityQuery()
        query.range = .hour
        let hour = try store.eventsPage(query, now: now)
        XCTAssertEqual(hour.total, 1)
        XCTAssertEqual(hour.events.first?.count, 4)
        XCTAssertTrue(hour.events.first?.id.hasPrefix("b") ?? false)
        query.range = .twelveHours
        XCTAssertEqual(try store.eventsPage(query, now: now).events.map(\.user), ["root", "admin"])
        query.range = .week
        XCTAssertTrue(try store.eventsPage(query, now: now).events.allSatisfy { $0.id.hasPrefix("f") })
    }

    func testTheSecondMigrationAddsTheTableToAnOldDatabase() throws {
        let old = try Database(path: ":memory:")
        try Migrations.run([SecurityDatabase.steps[0]], on: old)
        try old.execute("INSERT INTO failed_daily (day, machine, count, last_seen) VALUES ('2026-10-30', 'a', 5, '2026-10-30T10:00:00Z')")
        try Migrations.run(SecurityDatabase.steps, on: old)
        XCTAssertEqual(try old.query("SELECT COUNT(*) AS n FROM failed_buckets").first?.int("n"), 0)
        XCTAssertEqual(try old.query("SELECT SUM(count) AS n FROM failed_daily").first?.int("n"), 5)
    }
}
