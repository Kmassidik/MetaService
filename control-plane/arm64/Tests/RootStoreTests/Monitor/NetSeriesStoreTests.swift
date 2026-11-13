import XCTest
import RootCore
@testable import RootStore

final class NetSeriesStoreTests: XCTestCase {
    private var database: Database!
    private var store: NetMinuteStore!
    /// Minute 600 is epoch 36 000, the start of a 120-second bucket.
    private let firstMinute = 600
    private let bucketSeconds = 120
    private let everything = 100_000

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = NetMinuteStore(database)
    }

    private func minute(_ machine: String, _ index: Int, inBytes: Double = 60, outBytes: Double = 12,
                        inPeak: Double = 5, outPeak: Double = 1) -> NetMinute {
        NetMinute(machineId: machine, minute: index, inBytes: inBytes, outBytes: outBytes, inPeakBps: inPeak, outPeakBps: outPeak, samples: 1)
    }

    private func series(_ machine: String = "a", limit: Int = 1_000) throws -> [NetSeriesPoint] {
        try store.series(machineId: machine, sinceMinute: 0, untilMinute: everything, bucketSeconds: bucketSeconds, limit: limit)
    }

    func testNetSeriesThreeHoursGiveTheRightAveragesAndPeaksIn120SecondBuckets() throws {
        let threeHours = 180
        let minutes = (0..<threeHours).map { offset in
            minute("a", firstMinute + offset, inPeak: offset % 2 == 0 ? 5 : 9, outPeak: offset % 2 == 0 ? 1 : 2)
        }
        try store.record(minutes)
        let points = try series()
        XCTAssertEqual(points.count, threeHours / 2)
        XCTAssertEqual(points.first, NetSeriesPoint(t: 36_000, inBps: 1, outBps: 0.2, inPeakBps: 9, outPeakBps: 2))
        XCTAssertEqual(points.last?.t, 36_000 + (threeHours / 2 - 1) * bucketSeconds)
    }

    func testNetSeriesAQuietBucketIsNotScaledUp() throws {
        try store.record([minute("a", 800, inBytes: 120, outBytes: 0, inPeak: 3, outPeak: 0)])
        XCTAssertEqual(try series(), [NetSeriesPoint(t: 48_000, inBps: 1, outBps: 0, inPeakBps: 3, outPeakBps: 0)])
    }

    func testNetSeriesEmptyBucketsAreNotReturned() throws {
        try store.record([minute("a", 600), minute("a", 700)])
        XCTAssertEqual(try series().map(\.t), [36_000, 42_000])
    }

    func testNetSeriesAnotherMachinesRowsAreNotMixedIn() throws {
        try store.record([minute("a", 600, inBytes: 60), minute("b", 600, inBytes: 9_999)])
        XCTAssertEqual(try series().map(\.inBps), [0.5])
    }

    func testNetSeriesTheLimitKeepsTheNewestPointsOldestFirst() throws {
        try store.record((0..<5).map { minute("a", firstMinute + 2 * $0) })
        XCTAssertEqual(try series(limit: 2).map(\.t), [36_360, 36_480])
    }

    func testNetSeriesOnlyTheAskedMinutesAreCounted() throws {
        try store.record([minute("a", 600), minute("a", 602), minute("a", 604)])
        let points = try store.series(machineId: "a", sinceMinute: 602, untilMinute: 605, bucketSeconds: bucketSeconds, limit: 1_000)
        XCTAssertEqual(points.map(\.t), [36_120, 36_240])
    }
}
