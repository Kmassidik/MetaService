import XCTest
import MSCore
import RootCore
@testable import RootStore

private final class FixedClock: Clock, @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_793_523_000)
}

/// A pretend helper: pages of failed logins numbered by cursor, or a failure.
private final class PretendHelper: SecurityHelperSource, @unchecked Sendable {
    enum Mode { case pages(Int), status(Int), silent, junk }
    private let lock = NSLock()
    private var modes: [String: Mode] = [:]
    private(set) var asked: [(machine: String, after: String?)] = []

    func set(_ machine: String, _ mode: Mode) { lock.lock(); modes[machine] = mode; lock.unlock() }

    func fetch(machine: String, after: String?, limit: Int) async -> SecurityFetch {
        lock.lock(); defer { lock.unlock() }
        asked.append((machine, after))
        switch modes[machine] ?? .pages(1) {
        case .silent: return .unreachable
        case .status(let code): return .reply(status: code, data: Data("{}".utf8))
        case .junk: return .reply(status: 200, data: Data("not json".utf8))
        case .pages(let pages): return .reply(status: 200, data: page(after: after, pages: pages, limit: limit))
        }
    }

    /// Cursor "n" means n full pages were read. Every page is `limit` events of one try each, until `pages` pages have been served; the last one is short.
    private func page(after: String?, pages: Int, limit: Int) -> Data {
        let done = Int(after ?? "0") ?? 0
        let events: [[String: Any]] = done + 1 < pages
            ? (0..<limit).map { _ in ["time": "2026-11-01T08:00:00Z", "type": "failed_login", "user": "root", "address": "45.1.1.1", "count": 1] }
            : [["time": "2026-11-01T08:00:00Z", "type": "failed_login", "user": "root", "address": "45.1.1.1", "count": 1]]
        return try! JSONSerialization.data(withJSONObject: ["cursor": String(done + 1), "reset": false, "events": events, "baseline": ["firewall": true]])
    }
}

final class SecurityPullerTests: XCTestCase {
    private var store: SecurityStore!
    private let helper = PretendHelper()
    private let clock = FixedClock()
    private var lines: [String] = []
    private var puller: SecurityPuller!

    override func setUpWithError() throws {
        let database = try Database(path: ":memory:")
        try Migrations.run(SecurityDatabase.steps, on: database)
        store = SecurityStore(database)
        let box = LineBox()
        puller = SecurityPuller(helper: helper, ledger: store, clock: clock) { box.add($0) }
        self.box = box
    }

    private var box: LineBox!

    func testAShortPageIsOnePageAndTheCursorIsKept() async throws {
        let outcome = await puller.pull("a")
        XCTAssertEqual(outcome, .pulled(pages: 1, events: 1))
        XCTAssertEqual(try store.cursor(machine: "a"), "1")
        XCTAssertEqual(try store.failedTotals(sinceDay: "2026-10-01"), ["a": 1])
    }

    func testFullPagesAreFollowedButOnlyFiveInOneTick() async throws {
        helper.set("a", .pages(9))
        let outcome = await puller.pull("a")
        XCTAssertEqual(outcome, .pulled(pages: SecurityPuller.maxPagesPerTick, events: SecurityPuller.maxPagesPerTick * SecurityPuller.pageSize))
        XCTAssertEqual(try store.cursor(machine: "a"), "5")
        XCTAssertEqual(helper.asked.map(\.after), [nil, "1", "2", "3", "4"])
        let next = await puller.pull("a")
        XCTAssertEqual(next, .pulled(pages: 4, events: 3 * SecurityPuller.pageSize + 1))
        XCTAssertEqual(try store.failedTotals(sinceDay: "2026-10-01"), ["a": 8 * SecurityPuller.pageSize + 1])
    }

    func testAFailingMachineNeverStopsTheOthers() async throws {
        helper.set("bad", .silent)
        helper.set("broken", .junk)
        helper.set("old", .status(404))
        await puller.tick(machines: ["bad", "broken", "old", "good"])
        XCTAssertEqual(try store.cursor(machine: "good"), "1")
        for machine in ["bad", "broken", "old"] { XCTAssertNil(try store.state(machine: machine), machine) }
    }

    func testEveryFailureHasAPlainOutcomeAndIsReportedOnceUntilItRecovers() async throws {
        helper.set("a", .status(500))
        let first = await puller.pull("a")
        XCTAssertEqual(first, .failed("the helper answered 500"))
        helper.set("a", .junk)
        let second = await puller.pull("a")
        guard case .failed(let reason) = second else { return XCTFail("a refused answer must fail") }
        XCTAssertTrue(reason.hasPrefix("the helper answer was refused"))
        await puller.tick(machines: ["a"])
        await puller.tick(machines: ["a"])
        XCTAssertEqual(box.lines.count, 1)
        helper.set("a", .pages(1))
        await puller.tick(machines: ["a"])
        XCTAssertEqual(box.lines.last, "security: a answers again")
        XCTAssertFalse(box.lines.joined().contains("token"))
    }

    func testAnAnswerThatCannotBeStoredLeavesTheCursorWhereItWas() async throws {
        _ = await puller.pull("a")
        try store.database.exec("CREATE TRIGGER no_failed BEFORE INSERT ON failed_daily BEGIN SELECT RAISE(ABORT, 'refused'); END; CREATE TRIGGER no_failed_up BEFORE UPDATE ON failed_daily BEGIN SELECT RAISE(ABORT, 'refused'); END;")
        let outcome = await puller.pull("a")
        XCTAssertEqual(outcome, .failed("the security database could not be written"))
        XCTAssertEqual(try store.cursor(machine: "a"), "1")
        XCTAssertEqual(try store.failedTotals(sinceDay: "2026-10-01"), ["a": 1])
    }
}

private final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return all }
    func add(_ line: String) { lock.lock(); all.append(line); lock.unlock() }
}
