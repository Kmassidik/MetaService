import XCTest
@testable import RootCore

final class OfficeDeltaTests: XCTestCase {
    private func wide(_ value: UInt64) -> OfficeCounter { OfficeCounter(value: value, wide: true) }
    private func narrow(_ value: UInt64) -> OfficeCounter { OfficeCounter(value: value, wide: false) }

    func testOfficeDeltaFirstReadingHasNoDelta() {
        XCTAssertNil(OfficeDelta.bytes(previous: nil, now: wide(100)))
    }

    func testOfficeDeltaNormalGrowthIsTheDifference() {
        XCTAssertEqual(OfficeDelta.bytes(previous: wide(100), now: wide(250)), 150)
    }

    func testOfficeDeltaSameValueIsZero() {
        XCTAssertEqual(OfficeDelta.bytes(previous: wide(100), now: wide(100)), 0)
    }

    func testOfficeDeltaThirtyTwoBitCounterWrapsOnce() {
        let modulus: UInt64 = 1 << 32
        XCTAssertEqual(OfficeDelta.bytes(previous: narrow(modulus - 1_000), now: narrow(500)), 1_500)
    }

    func testOfficeDeltaSixtyFourBitCounterThatWentDownIsAReset() {
        XCTAssertNil(OfficeDelta.bytes(previous: wide(1_000), now: wide(5)))
    }

    func testOfficeDeltaJumpBiggerThanFortyGigabitsIsNil() {
        XCTAssertNil(OfficeDelta.bytes(previous: wide(0), now: wide(6_000_000_000)))
    }

    func testOfficeDeltaJumpOfExactlyTheLimitIsKept() {
        XCTAssertEqual(OfficeDelta.bytes(previous: wide(0), now: wide(5_000_000_000)), 5_000_000_000)
    }

    func testOfficeDeltaDifferentCounterKindsAreNotCompared() {
        XCTAssertNil(OfficeDelta.bytes(previous: narrow(100), now: wide(200)))
    }
}

final class OfficeMinuteAccumulatorTests: XCTestCase {
    private var accumulator = OfficeMinuteAccumulator()

    func testOfficeAccumulatorAddsBytesAndKeepsTheFasterPeak() {
        XCTAssertEqual(accumulator.add(wanIndex: 19, at: 600, inBytes: 600, outBytes: 300, seconds: 60), [])
        XCTAssertEqual(accumulator.add(wanIndex: 19, at: 630, inBytes: 1_200, outBytes: 60, seconds: 30), [])
        let open = accumulator.takeOpenMinutes()
        XCTAssertEqual(open, [OfficeMinute(wanIndex: 19, minute: 10, inBytes: 1_800, outBytes: 360, inPeakBps: 40, outPeakBps: 5, samples: 2)])
    }

    func testOfficeAccumulatorFinishesTheMinuteWhenALaterOneArrives() {
        _ = accumulator.add(wanIndex: 19, at: 600, inBytes: 600, outBytes: 300, seconds: 60)
        let finished = accumulator.add(wanIndex: 19, at: 660, inBytes: 1_200, outBytes: 60, seconds: 60)
        XCTAssertEqual(finished, [OfficeMinute(wanIndex: 19, minute: 10, inBytes: 600, outBytes: 300, inPeakBps: 10, outPeakBps: 5, samples: 1)])
        XCTAssertEqual(accumulator.takeOpenMinutes().map(\.minute), [11])
    }

    func testOfficeAccumulatorTwoWansDoNotMix() {
        _ = accumulator.add(wanIndex: 19, at: 600, inBytes: 600, outBytes: 0, seconds: 60)
        _ = accumulator.add(wanIndex: 20, at: 660, inBytes: 999, outBytes: 0, seconds: 60)
        let finished = accumulator.add(wanIndex: 19, at: 660, inBytes: 60, outBytes: 0, seconds: 60)
        XCTAssertEqual(finished.map(\.wanIndex), [19])
        XCTAssertEqual(finished.map(\.inBytes), [600])
        let open = accumulator.takeOpenMinutes().sorted { $0.wanIndex < $1.wanIndex }
        XCTAssertEqual(open.map(\.wanIndex), [19, 20])
        XCTAssertEqual(open.map(\.inBytes), [60, 999])
    }

    func testOfficeAccumulatorIgnoresAnIntervalNotNewerThanTheLastOne() {
        _ = accumulator.add(wanIndex: 19, at: 600, inBytes: 600, outBytes: 0, seconds: 60)
        XCTAssertEqual(accumulator.add(wanIndex: 19, at: 600, inBytes: 600, outBytes: 0, seconds: 60), [])
        XCTAssertEqual(accumulator.takeOpenMinutes().map(\.samples), [1])
    }

    func testOfficeAccumulatorIgnoresAnIntervalWithNoSeconds() {
        XCTAssertEqual(accumulator.add(wanIndex: 19, at: 600, inBytes: 600, outBytes: 0, seconds: 0), [])
        XCTAssertEqual(accumulator.takeOpenMinutes(), [])
    }
}
