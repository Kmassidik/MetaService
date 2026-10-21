import XCTest
@testable import RootCore

final class TerminalTicketsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let key = ConsoleKey(machine: "mini", workload: "vm-1")
    private let token = String(repeating: "a", count: 43)

    func testTheOperatorWhoAskedCanUseItOnce() {
        let book = TerminalTickets()
        book.issue(token: token, operatorName: "kurnia", key: key, now: now)
        XCTAssertEqual(book.redeem(token: token, operatorName: "kurnia", now: now.addingTimeInterval(1)), key)
        XCTAssertNil(book.redeem(token: token, operatorName: "kurnia", now: now.addingTimeInterval(2)), "single use")
    }

    func testAnotherOperatorIsRefusedAndTheTicketIsBurned() {
        let book = TerminalTickets()
        book.issue(token: token, operatorName: "kurnia", key: key, now: now)
        XCTAssertNil(book.redeem(token: token, operatorName: "mallory", now: now))
        XCTAssertNil(book.redeem(token: token, operatorName: "kurnia", now: now), "a wrong try burns it")
    }

    func testItDiesAfter30Seconds() {
        let book = TerminalTickets()
        book.issue(token: token, operatorName: "kurnia", key: key, now: now)
        XCTAssertNil(book.redeem(token: token, operatorName: "kurnia", now: now.addingTimeInterval(30)))
        book.issue(token: token, operatorName: "kurnia", key: key, now: now)
        XCTAssertEqual(book.redeem(token: token, operatorName: "kurnia", now: now.addingTimeInterval(29)), key)
    }

    func testGuessedAndHostileTicketsOpenNothing() {
        let book = TerminalTickets()
        book.issue(token: token, operatorName: "kurnia", key: key, now: now)
        for guess in ["", "x", token + "b", String(token.dropLast()), "../../etc/passwd", String(repeating: "a", count: 10_000)] {
            XCTAssertNil(book.redeem(token: guess, operatorName: "kurnia", now: now), guess)
        }
        XCTAssertEqual(book.redeem(token: token, operatorName: "kurnia", now: now), key, "guesses do not burn the real one")
    }

    func testTwoTicketsAreIndependent() {
        let book = TerminalTickets()
        let other = ConsoleKey(machine: "mini", workload: "vm-2")
        book.issue(token: "one", operatorName: "kurnia", key: key, now: now)
        book.issue(token: "two", operatorName: "kurnia", key: other, now: now)
        XCTAssertEqual(book.redeem(token: "two", operatorName: "kurnia", now: now), other)
        XCTAssertEqual(book.redeem(token: "one", operatorName: "kurnia", now: now), key)
    }
}
