import XCTest
@testable import RootCore

final class ScreenSessionsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private func later(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testOneSessionPerMachineAndItStartsAsViewOnly() throws {
        var book = ScreenSessionBook()
        let first = try book.open(machine: "mini", operatorName: "kurnia", ticket: "t1", now: start)
        XCTAssertEqual(first.mode, .view)
        XCTAssertThrowsError(try book.open(machine: "mini", operatorName: "kurnia", ticket: "t2", now: start)) { XCTAssertEqual($0 as? ScreenRefusal, .alreadyOpen) }
        XCTAssertNoThrow(try book.open(machine: "other", operatorName: "kurnia", ticket: "t3", now: start))
    }

    func testATicketBelongsToItsOperator() throws {
        var book = ScreenSessionBook()
        _ = try book.open(machine: "mini", operatorName: "kurnia", ticket: "t1", now: start)
        XCTAssertThrowsError(try book.use(ticket: "t1", operatorName: "someone", now: start)) { XCTAssertEqual($0 as? ScreenRefusal, .noSuchSession) }
        XCTAssertThrowsError(try book.use(ticket: "nope", operatorName: "kurnia", now: start))
        XCTAssertNil(book.close(ticket: "t1", operatorName: "someone"), "another operator cannot close it")
    }

    func testControlNeedsItsOwnConfirm() throws {
        var book = ScreenSessionBook()
        _ = try book.open(machine: "mini", operatorName: "kurnia", ticket: "t1", now: start)
        XCTAssertThrowsError(try book.takeControl(ticket: "t1", operatorName: "kurnia", confirmed: false, now: start)) { XCTAssertEqual($0 as? ScreenRefusal, .needsConfirm) }
        XCTAssertEqual(try book.use(ticket: "t1", operatorName: "kurnia", now: start).mode, .view)
        XCTAssertEqual(try book.takeControl(ticket: "t1", operatorName: "kurnia", confirmed: true, now: start).mode, .control)
    }

    func testAQuietSessionEndsAndActivityKeepsItAlive() throws {
        var book = ScreenSessionBook(idleSeconds: 600, maxSeconds: 3600)
        _ = try book.open(machine: "mini", operatorName: "kurnia", ticket: "t1", now: start)
        _ = try book.use(ticket: "t1", operatorName: "kurnia", now: later(500))
        _ = try book.use(ticket: "t1", operatorName: "kurnia", now: later(1000))
        XCTAssertThrowsError(try book.use(ticket: "t1", operatorName: "kurnia", now: later(1700))) { XCTAssertEqual($0 as? ScreenRefusal, .ended("The session was idle for too long.")) }
        XCTAssertThrowsError(try book.use(ticket: "t1", operatorName: "kurnia", now: later(1701)), "an ended session is gone") { XCTAssertEqual($0 as? ScreenRefusal, .noSuchSession) }
    }

    func testTheMaximumLengthEndsEvenAnActiveSession() throws {
        var book = ScreenSessionBook(idleSeconds: 600, maxSeconds: 3600)
        _ = try book.open(machine: "mini", operatorName: "kurnia", ticket: "t1", now: start)
        for minute in stride(from: 5, through: 55, by: 5) { _ = try book.use(ticket: "t1", operatorName: "kurnia", now: later(TimeInterval(minute * 60))) }
        XCTAssertThrowsError(try book.use(ticket: "t1", operatorName: "kurnia", now: later(3601 + 0))) { XCTAssertEqual($0 as? ScreenRefusal, .ended("The session reached its maximum length.")) }
    }

    func testAnEndedSessionDoesNotBlockTheNextOpen() throws {
        var book = ScreenSessionBook(idleSeconds: 60, maxSeconds: 3600)
        _ = try book.open(machine: "mini", operatorName: "kurnia", ticket: "t1", now: start)
        XCTAssertNoThrow(try book.open(machine: "mini", operatorName: "kurnia", ticket: "t2", now: later(120)))
    }

    func testRemovingAMachineClosesItsSessions() throws {
        var book = ScreenSessionBook()
        _ = try book.open(machine: "mini", operatorName: "kurnia", ticket: "t1", now: start)
        _ = try book.open(machine: "other", operatorName: "kurnia", ticket: "t2", now: start)
        XCTAssertEqual(book.closeAll(machine: "mini").map(\.ticket), ["t1"])
        XCTAssertEqual(book.open.map(\.ticket), ["t2"])
    }

    func testTicketsMayHoldDashAndUnderscoreButNothingElse() {
        XCTAssertTrue(ScreenSessionBook.isValidTicket("Ab3-_x9"), "base64url text, as the random ticket is made")
        for bad in ["", "a/b", "a b", "a.b", "../x", "é", String(repeating: "a", count: 65)] { XCTAssertFalse(ScreenSessionBook.isValidTicket(bad), bad) }
    }
}
