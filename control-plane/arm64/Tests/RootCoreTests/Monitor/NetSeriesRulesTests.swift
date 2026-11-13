import XCTest
@testable import RootCore

final class NetSeriesRulesTests: XCTestCase {
    func testNetSeriesRangeAMissingTextIsTheLastDay() {
        XCTAssertEqual(NetSeriesRange.parse(nil), .h24)
    }

    func testNetSeriesRangeEachAcceptedTextParses() {
        XCTAssertEqual(NetSeriesRange.parse("24h"), .h24)
        XCTAssertEqual(NetSeriesRange.parse("7d"), .d7)
        XCTAssertEqual(NetSeriesRange.parse("30d"), .d30)
    }

    func testNetSeriesRangeAnyOtherTextIsRefused() {
        XCTAssertNil(NetSeriesRange.parse("1h"))
        XCTAssertNil(NetSeriesRange.parse(""))
        XCTAssertNil(NetSeriesRange.parse("24H"))
    }

    func testNetSeriesRangeBucketsGiveTheContractPointCounts() {
        XCTAssertEqual(NetSeriesRange.h24.windowSeconds / NetSeriesRange.h24.bucketSeconds, 720)
        XCTAssertEqual(NetSeriesRange.d7.windowSeconds / NetSeriesRange.d7.bucketSeconds, 672)
        XCTAssertEqual(NetSeriesRange.d30.windowSeconds / NetSeriesRange.d30.bucketSeconds, 720)
        XCTAssertEqual([NetSeriesRange.h24.bucketSeconds, NetSeriesRange.d7.bucketSeconds, NetSeriesRange.d30.bucketSeconds], [120, 900, 3_600])
    }

    func testNetSeriesRangeStartIsTheWindowBeforeNow() {
        XCTAssertEqual(NetSeriesRange.d7.start(now: 1_000_000), 1_000_000 - 604_800)
    }

    func testNetSeriesFromBucketDividesTheBytesByTheWholeWidth() {
        let point = NetSeriesPoint.fromBucket(start: 600, inBytes: 120, outBytes: 0, inPeakBps: 3, outPeakBps: 0, bucketSeconds: 120)
        XCTAssertEqual(point, NetSeriesPoint(t: 600, inBps: 1, outBps: 0, inPeakBps: 3, outPeakBps: 0))
    }

    func testNetSeriesJsonKeysAreSnakeCase() throws {
        let point = NetSeriesPoint(t: 1, inBps: 2, outBps: 3, inPeakBps: 4, outPeakBps: 5)
        let data = try JSONEncoder().encode(NetSeriesReply(range: "24h", bucketSeconds: 120, points: [point]))
        let reply = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let points = try XCTUnwrap(reply["points"] as? [[String: Any]])
        XCTAssertEqual(Set(reply.keys), ["range", "bucket_seconds", "points"])
        XCTAssertEqual(Set(points[0].keys), ["t", "in_bps", "out_bps", "in_peak_bps", "out_peak_bps"])
        XCTAssertEqual(reply["bucket_seconds"] as? Int, 120)
    }
}
