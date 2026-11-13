import XCTest
import RootCore
@testable import RootStore

final class OfficeMinuteStoreTests: XCTestCase {
    private var database: Database!
    private var store: OfficeMinuteStore!

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = OfficeMinuteStore(database)
    }

    private func minute(_ wan: Int, _ index: Int, inBytes: Double = 100, outBytes: Double = 10,
                        inPeak: Double = 5, outPeak: Double = 1, samples: Int = 1) -> OfficeMinute {
        OfficeMinute(wanIndex: wan, minute: index, inBytes: inBytes, outBytes: outBytes, inPeakBps: inPeak, outPeakBps: outPeak, samples: samples)
    }

    func testOfficeSchemaIsAtVersion34() throws {
        XCTAssertEqual(Migrations.latest, 34)
        XCTAssertEqual(try database.query("SELECT MAX(version) AS v FROM schema_version").first?.int("v"), 34)
    }

    func testOfficeAWrittenAgainMinuteAddsBytesAndKeepsTheHigherPeak() throws {
        try store.record([minute(19, 10, inBytes: 100, outBytes: 10, inPeak: 50, outPeak: 1, samples: 2)])
        try store.record([minute(19, 10, inBytes: 40, outBytes: 5, inPeak: 20, outPeak: 9, samples: 1)])
        let figures = try store.usage(wanIndex: 19, since: 0, until: 100_000)
        XCTAssertEqual(figures, NetUsageFigures(inBytes: 140, outBytes: 15, inPeakBps: 50, outPeakBps: 9))
    }

    func testOfficeUsageSumsOnlyTheAskedWindow() throws {
        try store.record([minute(19, 10), minute(19, 20, inBytes: 1_000), minute(19, 30, inBytes: 10_000)])
        XCTAssertEqual(try store.usage(wanIndex: 19, since: 10 * 60, until: 20 * 60).inBytes, 100)
    }

    func testOfficeUsageIsKeptPerWanInterface() throws {
        try store.record([minute(19, 10, inBytes: 100), minute(20, 10, inBytes: 999)])
        XCTAssertEqual(try store.usage(wanIndex: 19, since: 0, until: 100_000).inBytes, 100)
        XCTAssertEqual(try store.usage(wanIndex: 21, since: 0, until: 100_000).inBytes, 0)
    }

    /// 16:59 UTC is 23:59 on the same day in UTC+7; 17:01 UTC is 00:01 the next day. Two different local days.
    func testOfficeDailyTotalsCutDaysAtOfficeMidnight() throws {
        let beforeMidnight = 1_794_675_540 / 60
        let afterMidnight = 1_794_675_660 / 60
        try store.record([minute(19, beforeMidnight, inBytes: 100), minute(20, afterMidnight, inBytes: 200)])
        let days = try store.dailyTotals(sinceMinute: 0, untilMinute: afterMidnight + 1, offsetMinutes: 420)
        XCTAssertEqual(days.map(\.dayStart), [1_794_589_200, 1_794_675_600])
        XCTAssertEqual(days.map(\.inBytes), [100, 200])
    }

    func testOfficeDailyTotalsAddAllWanInterfacesOfTheSameMinute() throws {
        try store.record([minute(19, 29_911_259, inBytes: 100), minute(20, 29_911_259, inBytes: 50)])
        let days = try store.dailyTotals(sinceMinute: 0, untilMinute: 40_000_000, offsetMinutes: 420)
        XCTAssertEqual(days.map(\.inBytes), [150])
    }

    func testOfficeDeleteOlderThanRemovesOnlyTheOldMinutes() throws {
        try store.record([minute(19, 10), minute(19, 20), minute(20, 5)])
        try store.deleteOlderThan(minute: 15)
        XCTAssertEqual(try store.usage(wanIndex: 19, since: 0, until: 100_000).inBytes, 100)
        XCTAssertEqual(try store.usage(wanIndex: 20, since: 0, until: 100_000).inBytes, 0)
    }
}
