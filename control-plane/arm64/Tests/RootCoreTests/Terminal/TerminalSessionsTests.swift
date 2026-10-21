import XCTest
@testable import RootCore

final class TerminalSessionsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func key(_ n: Int) -> ConsoleKey { ConsoleKey(machine: "mini", workload: "vm-\(n)") }

    func testOneConsolePerVm() throws {
        let book = TerminalSessions()
        try book.reserve(key(1), now: now)
        XCTAssertThrowsError(try book.reserve(key(1), now: now)) { XCTAssertEqual($0 as? ConsoleRefusal, .alreadyOpen) }
        XCTAssertTrue(book.open(key(1), now: now))
        XCTAssertThrowsError(try book.reserve(key(1), now: now)) { XCTAssertEqual($0 as? ConsoleRefusal, .alreadyOpen) }
    }

    func testFourInTotal() throws {
        let book = TerminalSessions()
        for n in 1...4 { try book.reserve(key(n), now: now) }
        XCTAssertThrowsError(try book.reserve(key(5), now: now)) { XCTAssertEqual($0 as? ConsoleRefusal, .tooMany) }
        book.close(key(2), now: now)
        XCTAssertNoThrow(try book.reserve(key(5), now: now))
    }

    func testAHeldPlaceLapsesWithItsTicket() throws {
        let book = TerminalSessions()
        for n in 1...4 { try book.reserve(key(n), now: now) }
        let later = now.addingTimeInterval(31)
        XCTAssertFalse(book.open(key(1), now: later), "too late")
        XCTAssertNoThrow(try book.reserve(key(5), now: later))
        XCTAssertEqual(book.count, 1)
    }

    func testIdleFor15MinutesEndsIt() throws {
        let book = TerminalSessions()
        try book.reserve(key(1), now: now)
        XCTAssertTrue(book.open(key(1), now: now))
        XCTAssertNil(book.endReason(key(1), now: now.addingTimeInterval(899)))
        book.touch(key(1), now: now.addingTimeInterval(899))
        XCTAssertNil(book.endReason(key(1), now: now.addingTimeInterval(1_700)))
        XCTAssertEqual(book.endReason(key(1), now: now.addingTimeInterval(899 + 900)), .idle)
    }

    func testEightHoursIsTheLongestEvenWhenBusy() throws {
        let book = TerminalSessions()
        try book.reserve(key(1), now: now)
        XCTAssertTrue(book.open(key(1), now: now))
        let nearEnd = now.addingTimeInterval(8 * 3600 - 1)
        book.touch(key(1), now: nearEnd)
        XCTAssertNil(book.endReason(key(1), now: nearEnd))
        XCTAssertEqual(book.endReason(key(1), now: now.addingTimeInterval(8 * 3600)), .tooLong)
    }

    func testAskedEndsWinAndReachOnlyThatVmOrMachine() throws {
        let book = TerminalSessions()
        let elsewhere = ConsoleKey(machine: "studio", workload: "vm-1")
        for k in [key(1), key(2), elsewhere] {
            try book.reserve(k, now: now)
            XCTAssertTrue(book.open(k, now: now))
        }
        book.requestEnd(key(1), .vmStopped)
        XCTAssertEqual(book.endReason(key(1), now: now), .vmStopped)
        XCTAssertNil(book.endReason(key(2), now: now))
        book.requestEnd(machine: "mini", .machineRemoved)
        XCTAssertEqual(book.endReason(key(2), now: now), .machineRemoved)
        XCTAssertNil(book.endReason(elsewhere, now: now))
    }

    func testCloseFreesThePlaceAndCountsSeconds() throws {
        let book = TerminalSessions()
        try book.reserve(key(1), now: now)
        XCTAssertTrue(book.open(key(1), now: now))
        XCTAssertEqual(book.close(key(1), now: now.addingTimeInterval(42)), 42)
        XCTAssertEqual(book.close(key(1), now: now.addingTimeInterval(50)), 0)
        XCTAssertNoThrow(try book.reserve(key(1), now: now))
    }

    func testAPlaceCannotBeOpenedTwice() throws {
        let book = TerminalSessions()
        try book.reserve(key(1), now: now)
        XCTAssertTrue(book.open(key(1), now: now))
        XCTAssertFalse(book.open(key(1), now: now))
        XCTAssertFalse(book.open(key(9), now: now))
    }
}
