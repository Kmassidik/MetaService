import XCTest
import RootCore
@testable import RootStore

final class SecurityStoreTests: XCTestCase {
    private var database: Database!
    private var store: SecurityStore!
    private let now = Date(timeIntervalSince1970: 1_793_523_000) // 2026-11-01T08:50:00Z

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.run(SecurityDatabase.steps, on: database)
        store = SecurityStore(database)
    }

    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private func event(_ type: SecurityEventType, at time: Date, user: String? = "root", address: String? = "45.1.1.1", count: Int = 1, until: Date? = nil, method: String? = nil) -> SecurityHelperEvent {
        SecurityHelperEvent(time: time, type: type, user: user, address: address, method: method, count: type == .failedLogin ? count : 1, until: until, detail: nil)
    }

    private func pull(_ events: [SecurityHelperEvent], cursor: String = "c1", reset: Bool = false, baseline: SecurityBaseline = .unknown) -> SecurityPull {
        SecurityPull(cursor: cursor, reset: reset, events: events, baseline: baseline, received: events.count, dropped: 0)
    }

    private func total(_ table: String) throws -> Int {
        switch table {
        case "events": return try database.query("SELECT COUNT(*) AS n FROM events").first?.int("n") ?? -1
        default: return try database.query("SELECT COALESCE(SUM(count), 0) AS n FROM failed_daily").first?.int("n") ?? -1
        }
    }

    func testTheSecurityDatabaseHasItsOwnVersion() throws {
        XCTAssertEqual(try database.query("SELECT MAX(version) AS v FROM schema_version").first?.int("v"), SecurityDatabase.latest)
        XCTAssertTrue(try database.query("SELECT name FROM sqlite_master WHERE name = 'machines'").isEmpty)
        try Migrations.run(SecurityDatabase.steps, on: database)
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM schema_version").first?.int("n"), SecurityDatabase.latest)
    }

    func testFailedLoginsAreAddedToTheDayAndOthersAreStoredOneByOne() throws {
        try store.store(pull([event(.failedLogin, at: ago(100), count: 3), event(.failedLogin, at: ago(50), count: 2), event(.login, at: ago(40), method: "key"), event(.blocked, at: ago(30))]), machine: "a", now: now)
        XCTAssertEqual(try total("failed"), 5)
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM failed_daily").first?.int("n"), 1)
        XCTAssertEqual(try total("events"), 2)
        XCTAssertEqual(try store.cursor(machine: "a"), "c1")
        XCTAssertEqual(try store.state(machine: "a")?.lastReported, "2026-11-01T08:50:00Z")
    }

    func testAnUnknownUserAndAddressStillCountOnce() throws {
        try store.store(pull([event(.failedLogin, at: ago(10), user: nil, address: nil), event(.failedLogin, at: ago(5), user: nil, address: nil)]), machine: "a", now: now)
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM failed_daily").first?.int("n"), 1)
        XCTAssertEqual(try total("failed"), 2)
    }

    func testAFailedPageChangesNothingNotEvenTheCursor() throws {
        try store.store(pull([event(.failedLogin, at: ago(100))], cursor: "old"), machine: "a", now: now)
        try database.exec("CREATE TRIGGER no_logins BEFORE INSERT ON events WHEN NEW.type = 'login' BEGIN SELECT RAISE(ABORT, 'refused'); END;")
        XCTAssertThrowsError(try store.store(pull([event(.failedLogin, at: ago(50), count: 9), event(.login, at: ago(40))], cursor: "new"), machine: "a", now: now))
        XCTAssertEqual(try store.cursor(machine: "a"), "old")
        XCTAssertEqual(try total("failed"), 1)
    }

    func testAskingAgainFromTheStoredCursorDoesNotCountTwice() throws {
        let page = pull([event(.failedLogin, at: ago(100), count: 4)], cursor: "c2")
        try store.store(page, machine: "a", now: now)
        XCTAssertEqual(try store.cursor(machine: "a"), "c2")
        // The cursor moved with the page, so the puller asks for what comes after it and never sends this page again.
        try store.store(pull([], cursor: "c2"), machine: "a", now: now)
        XCTAssertEqual(try total("failed"), 4)
    }

    func testAResetStoresTheNewCursorAndDeletesNothing() throws {
        try store.store(pull([event(.login, at: ago(100)), event(.failedLogin, at: ago(100), count: 2)]), machine: "a", now: now)
        try store.store(pull([event(.login, at: ago(10))], cursor: "fresh", reset: true), machine: "a", now: now)
        XCTAssertEqual(try store.cursor(machine: "a"), "fresh")
        XCTAssertEqual(try total("events"), 2)
        XCTAssertEqual(try total("failed"), 2)
    }

    func testEventsOlderThanTheRetentionAreNotStored() throws {
        let old = ago(100 * 86_400)
        try store.store(pull([event(.login, at: old), event(.failedLogin, at: old, count: 7)]), machine: "a", now: now)
        XCTAssertEqual(try total("events"), 0)
        XCTAssertEqual(try total("failed"), 0)
    }

    func testRetentionDeletesOldRowsAndKeepsAMachineThatWasRemoved() throws {
        try store.store(pull([event(.login, at: ago(10))]), machine: "gone", now: ago(80 * 86_400))
        try database.execute("INSERT INTO events (time, machine, type, count) VALUES (?, 'gone', 'login', 1)", [.text(SecurityTime.text(ago(89 * 86_400)))])
        try database.execute("INSERT INTO events (time, machine, type, count) VALUES (?, 'gone', 'login', 1)", [.text(SecurityTime.text(ago(91 * 86_400)))])
        try database.execute("INSERT INTO failed_daily (day, machine, count, last_seen) VALUES (?, 'gone', 5, ?)", [.text(SecurityTime.day(ago(91 * 86_400))), .text(SecurityTime.text(ago(91 * 86_400)))])
        try database.execute("INSERT INTO failed_daily (day, machine, count, last_seen) VALUES (?, 'gone', 6, ?)", [.text(SecurityTime.day(ago(89 * 86_400))), .text(SecurityTime.text(ago(89 * 86_400)))])
        try store.prune(now: now)
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM events WHERE time < ?", [.text(SecurityTime.text(SecurityTime.retentionCutoff(now: now)))]).first?.int("n"), 0)
        XCTAssertEqual(try total("events"), 2)
        XCTAssertEqual(try total("failed"), 6)
    }

    func testBlockedNowFollowsTheLatestEventAndTheEndOfTheBan() throws {
        try store.store(pull([
            event(.blocked, at: ago(500), address: "1.1.1.1"), event(.unblocked, at: ago(400), address: "1.1.1.1"),
            event(.blocked, at: ago(300), address: "2.2.2.2"),
            event(.blocked, at: ago(300), address: "3.3.3.3", until: ago(100)),
            event(.blocked, at: ago(300), address: "4.4.4.4", until: now.addingTimeInterval(600)),
            event(.unblocked, at: ago(400), address: "5.5.5.5"), event(.blocked, at: ago(200), address: "5.5.5.5"),
            event(.failedLogin, at: ago(250), address: "2.2.2.2", count: 12),
        ]), machine: "a", now: now)
        let rows = SecurityBlocking.inForce(try store.blockCandidates(attemptsSinceDay: "2026-10-25"), now: now)
        XCTAssertEqual(Set(rows.map(\.address)), ["2.2.2.2", "4.4.4.4", "5.5.5.5"])
        XCTAssertEqual(rows.first { $0.address == "2.2.2.2" }?.attempts, 12)
        XCTAssertNil(rows.first { $0.address == "4.4.4.4" }?.attempts)
        XCTAssertNil(rows.first { $0.address == "2.2.2.2" }?.until)
    }

    func testTotalsAndTopListsFollowTheRange() throws {
        try store.store(pull([event(.failedLogin, at: ago(100), user: "root", address: "1.1.1.1", count: 5), event(.failedLogin, at: ago(100), user: "admin", address: "1.1.1.1", count: 2),
                              event(.failedLogin, at: ago(3 * 86_400), user: "root", address: "2.2.2.2", count: 1), event(.failedLogin, at: ago(40 * 86_400), user: "old", address: "3.3.3.3", count: 99),
                              event(.blocked, at: ago(100)), event(.blocked, at: ago(40 * 86_400))]), machine: "a", now: now)
        XCTAssertEqual(try store.failedTotals(sinceDay: SecurityRange.week.firstDay(now: now)), ["a": 8])
        XCTAssertEqual(try store.failedTotals(sinceDay: SecurityRange.quarter.firstDay(now: now)), ["a": 107])
        XCTAssertEqual(try store.blockedTotals(since: SecurityRange.week.start(now: now)), ["a": 1])
        XCTAssertEqual(try store.topUsers(sinceDay: "2026-10-25"), [SecurityTopRow(name: "root", count: 6), SecurityTopRow(name: "admin", count: 2)])
        XCTAssertEqual(try store.topAddresses(sinceDay: "2026-10-25").first, SecurityTopRow(name: "1.1.1.1", count: 7))
        XCTAssertEqual(try store.daily(sinceDay: "2026-10-25").map(\.failed), [1, 7])
    }

    func testTheTopListsHoldAtMostEightRows() throws {
        let events = (1...12).map { event(.failedLogin, at: ago(100), user: "user\($0)", address: "9.9.9.\($0)", count: $0) }
        try store.store(pull(events), machine: "a", now: now)
        XCTAssertEqual(try store.topUsers(sinceDay: "2026-10-25").count, 8)
        XCTAssertEqual(try store.topUsers(sinceDay: "2026-10-25").first?.name, "user12")
    }

    func testTheLogHoldsBothKindsNewestFirstWithRealPaging() throws {
        let events = (0..<30).map { event(.login, at: ago(Double($0 + 1) * 60), user: "u\($0)", method: "key") } + [event(.failedLogin, at: ago(30), user: "root", count: 4)]
        try store.store(pull(events), machine: "a", now: now)
        var query = SecurityQuery()
        query.pageSize = 10
        let first = try store.eventsPage(query, now: now)
        XCTAssertEqual(first.total, 31)
        XCTAssertEqual(first.events.count, 10)
        XCTAssertEqual(first.events.first?.type, "failed_login")
        XCTAssertEqual(first.events.first?.count, 4)
        XCTAssertNil(first.events[1].count)
        XCTAssertEqual(first.events[1].method, "key")
        query.page = 4
        let last = try store.eventsPage(query, now: now)
        XCTAssertEqual(last.events.count, 1)
        XCTAssertEqual(Set(first.events.map(\.id)).intersection(last.events.map(\.id)), [])
        query.page = 5
        XCTAssertEqual(try store.eventsPage(query, now: now).events.count, 0)
        XCTAssertEqual(try store.eventsPage(query, now: now).total, 31)
    }

    func testTheLogFiltersByMachineTypeTextAndRange() throws {
        try store.store(pull([event(.login, at: ago(100), user: "kurnia", address: "10.0.0.5"), event(.failedLogin, at: ago(90), user: "root", address: "45.1.1.1", count: 2),
                              event(.blocked, at: ago(80), user: nil, address: "45.1.1.1"), event(.login, at: ago(20 * 86_400), user: "old", address: "10.0.0.9")]), machine: "a", now: now)
        try store.store(pull([event(.login, at: ago(70), user: "other", address: "10.0.0.6")]), machine: "b", now: now)
        func run(_ change: (inout SecurityQuery) -> Void) throws -> SecurityEventsReply {
            var query = SecurityQuery()
            change(&query)
            return try store.eventsPage(query, now: now)
        }
        XCTAssertEqual(try run { _ in }.total, 4)
        XCTAssertEqual(try run { $0.machine = "b" }.events.map(\.user), ["other"])
        XCTAssertEqual(try run { $0.type = .failedLogin }.total, 1)
        XCTAssertEqual(try run { $0.type = .login }.total, 2)
        XCTAssertEqual(try run { $0.text = "45.1" }.total, 2)
        XCTAssertEqual(try run { $0.text = "KURN" }.events.map(\.user), ["kurnia"])
        XCTAssertEqual(try run { $0.range = .month }.total, 5)
        XCTAssertEqual(try run { $0.machine = "nobody" }.total, 0)
    }

    func testASearchTakesPercentAndUnderscoreAsPlainCharacters() throws {
        try store.store(pull([event(.login, at: ago(10), user: "a_b"), event(.login, at: ago(20), user: "axb")]), machine: "a", now: now)
        var query = SecurityQuery()
        query.text = "a_b"
        XCTAssertEqual(try store.eventsPage(query, now: now).events.map(\.user), ["a_b"])
        query.text = "%"
        XCTAssertEqual(try store.eventsPage(query, now: now).total, 0)
    }

    func testTheBaselineIsKeptAndReplacedByTheNextAnswer() throws {
        try store.store(pull([], baseline: SecurityBaseline(passwordLogin: true, banTool: "running", pendingUpdates: 3)), machine: "a", now: now)
        XCTAssertEqual(try store.state(machine: "a")?.baseline.passwordLogin, true)
        try store.store(pull([], baseline: SecurityBaseline(passwordLogin: false)), machine: "a", now: now)
        XCTAssertEqual(try store.state(machine: "a")?.baseline, SecurityBaseline(passwordLogin: false))
        XCTAssertNil(try store.state(machine: "never"))
    }
}
