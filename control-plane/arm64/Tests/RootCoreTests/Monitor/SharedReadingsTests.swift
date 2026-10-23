import XCTest
import MSCore
@testable import RootCore

private final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private actor Counter {
    private(set) var calls = 0
    private(set) var outcome: ReadingOutcome<Int> = .fresh(1)
    var delayNanoseconds: UInt64 = 0
    func set(_ value: ReadingOutcome<Int>) { outcome = value }
    func slow(_ nanoseconds: UInt64) { delayNanoseconds = nanoseconds }
    func fetch() async -> ReadingOutcome<Int> {
        calls += 1
        if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
        return outcome
    }
}

final class SharedReadingsTests: XCTestCase {
    private func make() -> (SharedReadings<Int>, TestClock, Counter) {
        let clock = TestClock()
        return (SharedReadings<Int>(clock: clock), clock, Counter())
    }

    func testTwoAskersInsideTheSharedReadingWindowCostOneHelperCall() async {
        let (readings, clock, counter) = make()
        let first = await readings.read("mini") { await counter.fetch() }
        clock.advance(1.4)
        let second = await readings.read("mini") { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(first.value, 1)
        XCTAssertEqual(second.value, 1)
    }

    func testASamplerStillTryingAHelperThatWentSilentDoesNotKeepItsLastNumbersAlive() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini") { await counter.fetch() }
        await counter.set(.unreachable)
        for _ in 0..<4 {
            clock.advance(10)
            _ = await readings.read("mini", keepsAlive: false) { await counter.fetch() }
        }
        let held = await readings.lastKnown("mini")
        XCTAssertNil(held.value, "nobody asked for 40 seconds: the last numbers are dropped, as before the sampler existed")
    }

    func testTheSamplerAndAPersonShareOneCallInsideTheSharedReadingWindow() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini", keepsAlive: false) { await counter.fetch() }
        clock.advance(1)
        _ = await readings.read("mini") { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 1)
    }

    func testAfterTheSharedReadingWindowTheHelperIsAskedAgain() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini") { await counter.fetch() }
        clock.advance(4.0)
        _ = await readings.read("mini") { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 2)
    }

    func testTwoReadsOneSecondApartShareOneHelperCall() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini") { await counter.fetch() }
        clock.advance(1)
        _ = await readings.read("mini") { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 1)
    }

    func testTwoReadsTwoSecondsApartMakeTwoHelperCalls() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini") { await counter.fetch() }
        clock.advance(2)
        _ = await readings.read("mini") { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 2)
    }

    func testManyAskersAtTheSameTimeShareOneCallInFlight() async {
        let (readings, _, counter) = make()
        await counter.slow(200_000_000)
        await withTaskGroup(of: Int?.self) { group in
            for _ in 0..<20 { group.addTask { await readings.read("mini") { await counter.fetch() }.value } }
            for await value in group { XCTAssertEqual(value, 1) }
        }
        let calls = await counter.calls
        XCTAssertEqual(calls, 1)
    }

    func testMachinesDoNotShareReadings() async {
        let (readings, _, counter) = make()
        _ = await readings.read("a") { await counter.fetch() }
        _ = await readings.read("b") { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 2)
    }

    func testAFailureIsKeptForTheSharedReadingWindowToo() async {
        let (readings, clock, counter) = make()
        await counter.set(.unreachable)
        let first = await readings.read("mini") { await counter.fetch() }
        clock.advance(1)
        _ = await readings.read("mini") { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(first.answer, .unreachable)
    }

    func testAfterAFailureTheLastGoodReadingIsStillOffered() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini") { await counter.fetch() }
        await counter.set(.unreachable)
        clock.advance(5)
        let reply = await readings.read("mini") { await counter.fetch() }
        XCTAssertEqual(reply.answer, .unreachable)
        XCTAssertEqual(reply.value, 1, "the last numbers are kept for the greyed view")
        XCTAssertNotNil(reply.fetchedAt)
    }

    func testAReadingNobodyAskedForInThirtySecondsIsDropped() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini") { await counter.fetch() }
        clock.advance(30.5)
        let dropped = await readings.lastKnown("mini")
        XCTAssertNil(dropped.value)
        let count = await readings.heldCount
        XCTAssertEqual(count, 0)
    }

    func testAskingKeepsAReadingAlive() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini") { await counter.fetch() }
        for _ in 0..<5 {
            clock.advance(20)
            _ = await readings.lastKnown("mini")
        }
        let alive = await readings.lastKnown("mini")
        XCTAssertEqual(alive.value, 1)
    }

    func testAnOldHelperIsRememberedAsThat() async {
        let (readings, _, counter) = make()
        await counter.set(.oldHelper)
        let reply = await readings.read("mini") { await counter.fetch() }
        XCTAssertEqual(reply.answer, .oldHelper)
        XCTAssertNil(reply.value)
    }

    // A reading with the extra part (the process list) also answers a request without it; the other way round it does not.

    func testAReadingWithDetailAlsoAnswersARequestWithoutDetail() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini", detailed: true) { await counter.fetch() }
        clock.advance(1)
        _ = await readings.read("mini", detailed: false) { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 1)
    }

    func testARequestWithDetailAfterOneWithoutAsksTheHelperAgainAtOnce() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini", detailed: false) { await counter.fetch() }
        clock.advance(1)
        _ = await readings.read("mini", detailed: true) { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 2)
    }

    func testOnceTheDetailedReadingIsHeldFurtherRequestsInsideTheSharedReadingWindowCostNothing() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini", detailed: false) { await counter.fetch() }
        clock.advance(1)
        _ = await readings.read("mini", detailed: true) { await counter.fetch() }
        clock.advance(1)
        _ = await readings.read("mini", detailed: true) { await counter.fetch() }
        _ = await readings.read("mini", detailed: false) { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 2)
    }

    func testAfterTheSharedReadingWindowAPlainRequestRefreshesWithoutDetailAndDetailIsAskedForAgain() async {
        let (readings, clock, counter) = make()
        _ = await readings.read("mini", detailed: true) { await counter.fetch() }
        clock.advance(4)
        _ = await readings.read("mini", detailed: false) { await counter.fetch() }
        _ = await readings.read("mini", detailed: true) { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 3)
    }

    func testAFailedCallIsNotRepeatedJustBecauseDetailWasAskedFor() async {
        let (readings, clock, counter) = make()
        await counter.set(.unreachable)
        _ = await readings.read("mini", detailed: false) { await counter.fetch() }
        clock.advance(1)
        _ = await readings.read("mini", detailed: true) { await counter.fetch() }
        let calls = await counter.calls
        XCTAssertEqual(calls, 1, "a dead helper is left alone for 1.5 seconds whatever is asked")
    }

    func testAskersWithDetailWhileAPlainCallIsRunningShareOneFollowUpCall() async {
        let (readings, _, counter) = make()
        await counter.slow(150_000_000)
        async let plain = readings.read("mini", detailed: false) { await counter.fetch() }
        try? await Task.sleep(nanoseconds: 30_000_000)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { _ = await readings.read("mini", detailed: true) { await counter.fetch() } } }
        }
        _ = await plain
        let calls = await counter.calls
        XCTAssertEqual(calls, 2)
    }
}
