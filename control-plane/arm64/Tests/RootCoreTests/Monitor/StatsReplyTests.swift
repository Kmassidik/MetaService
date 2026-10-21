import XCTest
@testable import RootCore

final class StatsReplyTests: XCTestCase {
    private let seen = "2026-10-21T10:00:00Z"
    private let fetched = Date(timeIntervalSince1970: 1_800_000_000)

    func testAMachineTheParentCallsOfflineAnswersOfflineWithTheLastReading() {
        let reply = StatsReply.make(machineOffline: true, lastSeen: seen, reading: .init(answer: .fresh, value: 7, fetchedAt: fetched))
        XCTAssertEqual(reply.state, "offline")
        XCTAssertEqual(reply.stats, 7)
        XCTAssertEqual(reply.lastSeen, seen)
    }

    func testAnOfflineMachineWithNothingHeldHasNullStats() {
        let reply = StatsReply<Int>.make(machineOffline: true, lastSeen: nil, reading: .init(answer: .unreachable, value: nil, fetchedAt: nil))
        XCTAssertEqual(reply.state, "offline")
        XCTAssertNil(reply.stats)
        XCTAssertNil(reply.fetchedAt)
    }

    func testAFreshReadingIsOnline() {
        let reply = StatsReply.make(machineOffline: false, lastSeen: seen, reading: .init(answer: .fresh, value: 5, fetchedAt: fetched))
        XCTAssertEqual(reply.state, "online")
        XCTAssertEqual(reply.stats, 5)
        XCTAssertEqual(reply.fetchedAt, "2027-01-15T08:00:00Z")
    }

    func testAnUnreachableHelperIsOfflineWithTheLastNumbers() {
        let reply = StatsReply.make(machineOffline: false, lastSeen: seen, reading: .init(answer: .unreachable, value: 3, fetchedAt: fetched))
        XCTAssertEqual(reply.state, "offline")
        XCTAssertEqual(reply.stats, 3)
    }

    func testAnOldHelperIsNamedAndHasNoNumbers() {
        let reply = StatsReply<Int>.make(machineOffline: false, lastSeen: seen, reading: .init(answer: .oldHelper, value: nil, fetchedAt: nil))
        XCTAssertEqual(reply.state, "old_helper")
        XCTAssertNil(reply.stats)
    }
}
