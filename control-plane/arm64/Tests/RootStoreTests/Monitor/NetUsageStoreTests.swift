import XCTest
import RootCore
@testable import RootStore

final class NetUsageStoreTests: XCTestCase {
    private var database: Database!
    private var store: NetMinuteStore!

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = NetMinuteStore(database)
    }

    private func minute(_ machine: String, _ index: Int, inBytes: Double = 100, outBytes: Double = 10,
                        inPeak: Double = 5, outPeak: Double = 1, samples: Int = 1) -> NetMinute {
        NetMinute(machineId: machine, minute: index, inBytes: inBytes, outBytes: outBytes, inPeakBps: inPeak, outPeakBps: outPeak, samples: samples)
    }

    func testNetUsageAWrittenAgainMinuteAddsBytesAndKeepsTheHigherPeak() throws {
        try store.record([minute("a", 10, inBytes: 100, outBytes: 10, inPeak: 50, outPeak: 1, samples: 2)])
        try store.record([minute("a", 10, inBytes: 40, outBytes: 5, inPeak: 20, outPeak: 9, samples: 1)])
        let figures = try store.usage(machineId: "a", since: 0, until: 100_000)
        XCTAssertEqual(figures, NetUsageFigures(inBytes: 140, outBytes: 15, inPeakBps: 50, outPeakBps: 9))
    }

    func testNetUsageUsageSumsOnlyTheAskedWindow() throws {
        try store.record([minute("a", 10), minute("a", 20, inBytes: 1_000), minute("a", 30, inBytes: 10_000)])
        let figures = try store.usage(machineId: "a", since: 10 * 60, until: 20 * 60)
        XCTAssertEqual(figures.inBytes, 100)
    }

    func testNetUsageUsageIsKeptPerMachine() throws {
        try store.record([minute("a", 10, inBytes: 100), minute("b", 10, inBytes: 999)])
        XCTAssertEqual(try store.usage(machineId: "a", since: 0, until: 100_000).inBytes, 100)
    }

    func testNetUsageAMachineWithNoDataHasZeros() throws {
        XCTAssertEqual(try store.usage(machineId: "none", since: 0, until: 100_000), NetUsageFigures(inBytes: 0, outBytes: 0, inPeakBps: 0, outPeakBps: 0))
    }

    /// 16:59 UTC is 23:59 on the same day in UTC+7; 17:01 UTC is 00:01 the next day. Two different local days.
    func testNetUsageDailyTotalsCutDaysAtOfficeMidnight() throws {
        let beforeMidnight = 1_794_675_540 / 60
        let afterMidnight = 1_794_675_660 / 60
        try store.record([minute("a", beforeMidnight, inBytes: 100), minute("a", afterMidnight, inBytes: 200)])
        let days = try store.dailyTotals(machineId: "a", sinceMinute: 0, untilMinute: afterMidnight + 1, offsetMinutes: 420)
        XCTAssertEqual(days.map(\.dayStart), [1_794_589_200, 1_794_675_600])
        XCTAssertEqual(days.map(\.inBytes), [100, 200])
    }

    func testNetUsageDailyTotalsWithNoMachineAddsAllMachines() throws {
        try store.record([minute("a", 29_911_259, inBytes: 100), minute("b", 29_911_259, inBytes: 50)])
        let days = try store.dailyTotals(machineId: nil, sinceMinute: 0, untilMinute: 40_000_000, offsetMinutes: 420)
        XCTAssertEqual(days.map(\.inBytes), [150])
    }

    func testNetUsageDeleteOlderThanRemovesOnlyTheOldMinutes() throws {
        try store.record([minute("a", 10), minute("a", 20), minute("b", 5)])
        try store.deleteOlderThan(minute: 15)
        XCTAssertEqual(try store.usage(machineId: "a", since: 0, until: 100_000).inBytes, 100)
        XCTAssertEqual(try store.usage(machineId: "b", since: 0, until: 100_000).inBytes, 0)
    }

    func testNetUsageSchemaIsAtVersion33() throws {
        XCTAssertEqual(Migrations.latest, 33)
        XCTAssertEqual(try database.query("SELECT MAX(version) AS v FROM schema_version").first?.int("v"), 33)
    }
}
