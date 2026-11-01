import XCTest
@testable import AgentCore

/// What the stubbed log was asked, and how much "time" each ask used.
private final class LogStub: @unchecked Sendable {
    var calls: [(start: Int, end: Int)] = []
    var clock: TimeInterval = 0
    var secondsPerCall: TimeInterval = 0
    var text = ""
    var failFromCall: Int?
    var now = securityEpoch("2026-11-01T08:00:00Z")

    func read(_ start: Int, _ end: Int, _ timeout: TimeInterval) async throws -> String {
        calls.append((start, end))
        clock += secondsPerCall
        if let failFromCall, calls.count >= failFromCall { throw CocoaError(.fileReadUnknown) }
        return text
    }
}

final class SecurityEventsReaderTests: XCTestCase {
    private let now = securityEpoch("2026-11-01T08:00:00Z")

    private func reader(_ stub: LogStub, budget: TimeInterval = 20, history: Int = 24 * 3600) -> SecurityEventsReader {
        SecurityEventsReader(zone: securityTestZone, budget: budget, history: history, now: { stub.now }, uptime: { stub.clock }, readLog: stub.read)
    }

    func testAFirstCallReadsTheHistoryInSixHourWindowsAndStopsJustBeforeNow() async throws {
        let stub = LogStub()
        let page = try await reader(stub).read(after: nil, limit: 500)
        let settled = now - SecurityEventsReader.settleSeconds
        XCTAssertEqual(stub.calls.count, 4, "24 hours is four windows, the last five seconds short")
        XCTAssertEqual(stub.calls.first?.start, now - 24 * 3600)
        XCTAssertEqual(stub.calls.first?.end, now - 24 * 3600 + 6 * 3600)
        XCTAssertEqual(stub.calls.last?.end, settled)
        XCTAssertEqual(page.cursor, "m1.\(settled)")
        XCTAssertFalse(page.reset)
        XCTAssertEqual(page.events, [])
    }

    func testConnectionsBecomeOneEventPerHourWithNoInventedNames() async throws {
        let stub = LogStub()
        stub.text = [sshLine("2026-11-01 14:10:00", pid: 1), sshLine("2026-11-01 14:20:00", pid: 2), sshLine("2026-11-01 14:30:00", pid: 1), sshLine("2026-11-01 14:55:30", pid: 3),
                     sshLine("2026-11-01 14:56:00", pid: 3, message: "Failed password for root from 6.6.6.6"), sshLine("2026-11-01 13:05:00", pid: 4)].joined(separator: "\n")
        let page = try await reader(stub).read(after: nil, limit: 500)
        XCTAssertEqual(page.events, [
            SecurityEvent(time: "2026-11-01T06:05:00Z", type: .failedLogin, count: 1, detail: "SSH connections (macOS does not log who tried)"),
            SecurityEvent(time: "2026-11-01T07:55:30Z", type: .failedLogin, count: 3, detail: "SSH connections (macOS does not log who tried)"),
        ])
        XCTAssertTrue(page.events.allSatisfy { $0.user == nil && $0.address == nil && $0.method == nil && $0.until == nil })
        XCTAssertFalse(String(describing: page).contains("6.6.6.6"), "log text never reaches the answer")
    }

    func testTheNextCallAsksTheLogOnlyForTheTimeAfterTheCursor() async throws {
        let stub = LogStub()
        let service = reader(stub)
        let first = try await service.read(after: nil, limit: 500)
        stub.calls = []
        let second = try await service.read(after: first.cursor, limit: 500)
        XCTAssertEqual(stub.calls.count, 0, "nothing new yet: the log is not run at all")
        XCTAssertEqual(second.cursor, first.cursor)
        stub.now = now + 90
        let third = try await service.read(after: first.cursor, limit: 500)
        XCTAssertEqual(stub.calls.map(\.start), [now - 5])
        XCTAssertEqual(stub.calls.map(\.end), [now + 85])
        XCTAssertEqual(third.cursor, "m1.\(now + 85)")
    }

    func testAConnectionSplitByACursorIsNotCountedTwice() async throws {
        let stub = LogStub()
        stub.text = sshLine("2026-11-01 14:58:20", pid: 7)
        let service = reader(stub, history: 3600)
        let first = try await service.read(after: nil, limit: 500)
        XCTAssertEqual(first.events.map(\.count), [1])
        stub.now = now + 60
        stub.text = sshLine("2026-11-01 14:58:20", pid: 7) + "\n" + sshLine("2026-11-01 14:59:59", pid: 7)
        let second = try await service.read(after: first.cursor, limit: 500)
        XCTAssertEqual(second.events, [], "the same process id logging again is the same connection")
    }

    func testGarbledFutureAndTooOldCursorsStartOverAndSayReset() async throws {
        for cursor in ["garbage", "m1.-4", "m1.\(now + 1000)", "m1.\(now - 10 * 24 * 3600)", "v1.a-x.f-x"] {
            let stub = LogStub()
            let page = try await reader(stub).read(after: cursor, limit: 500)
            XCTAssertTrue(page.reset, cursor)
            XCTAssertEqual(stub.calls.first?.start, now - 24 * 3600, cursor)
            XCTAssertTrue(page.cursor.hasPrefix("m1."), cursor)
        }
    }

    func testAnEmptyCursorIsNoCursorAndNotAReset() async throws {
        let stub = LogStub()
        let page = try await reader(stub).read(after: nil, limit: 500)
        XCTAssertFalse(page.reset)
    }

    func testTheLimitCutsAtAWholeHourAndTheCursorStopsThere() async throws {
        let stub = LogStub()
        stub.text = [sshLine("2026-11-01 10:10:00", pid: 1), sshLine("2026-11-01 11:10:00", pid: 2), sshLine("2026-11-01 12:10:00", pid: 3)].joined(separator: "\n")
        let service = reader(stub, history: 6 * 3600)
        let page = try await service.read(after: nil, limit: 2)
        XCTAssertEqual(page.events.map(\.time), ["2026-11-01T03:10:00Z", "2026-11-01T04:10:00Z"])
        XCTAssertEqual(page.cursor, "m1.\(securityEpoch("2026-11-01T05:00:00Z"))", "the end of the last hour that was given")
        let rest = try await service.read(after: page.cursor, limit: 2)
        XCTAssertEqual(rest.events.map(\.time), ["2026-11-01T05:10:00Z"], "the hour that did not fit comes next, counted once")
    }

    func testTheTimeBudgetStopsTheCallAndTheCursorSitsWhereReadingStopped() async throws {
        let stub = LogStub()
        stub.secondsPerCall = 15
        let page = try await reader(stub, budget: 20).read(after: nil, limit: 500)
        XCTAssertEqual(stub.calls.count, 2)
        XCTAssertEqual(page.cursor, "m1.\(now - 24 * 3600 + 12 * 3600)")
        XCTAssertFalse(page.reset)
    }

    func testAFailingLogIsAnErrorOnTheFirstWindowAndPartialLaterOn() async throws {
        let first = LogStub()
        first.failFromCall = 1
        do {
            _ = try await reader(first).read(after: nil, limit: 500)
            XCTFail("the first window failed")
        } catch let failure as SecurityLogFailure {
            XCTAssertTrue(failure.message.hasPrefix("the macOS log could not be read"))
        }
        let later = LogStub()
        later.failFromCall = 3
        let page = try await reader(later).read(after: nil, limit: 500)
        XCTAssertEqual(page.cursor, "m1.\(now - 24 * 3600 + 12 * 3600)", "two windows were read before the failure")
    }

    func testTheAnswerWritesNullsForWhatItDoesNotKnow() throws {
        let event = SecurityEvent(time: "2026-11-01T07:00:00Z", type: .failedLogin, count: 3, detail: "d")
        let answer = SecurityAnswer(cursor: "m1.1", reset: false, events: [event], baseline: SecurityBaseline(banTool: .notAvailable, firewall: false))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try JSONSerialization.jsonObject(with: encoder.encode(answer)) as! [String: Any]
        let first = (json["events"] as! [[String: Any]])[0]
        XCTAssertEqual(first["type"] as? String, "failed_login")
        for key in ["user", "address", "method", "until"] { XCTAssertTrue(first[key] is NSNull, key) }
        let baseline = json["baseline"] as! [String: Any]
        XCTAssertEqual(baseline["ban_tool"] as? String, "not_available")
        XCTAssertEqual(baseline["firewall"] as? Bool, false)
        for key in ["password_login", "auto_updates", "starts_after_reboot", "pending_updates"] { XCTAssertTrue(baseline[key] is NSNull, key) }
    }
}
