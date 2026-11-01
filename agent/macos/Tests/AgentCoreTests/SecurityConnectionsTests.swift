import XCTest
import MSCore
@testable import AgentCore

/// Fixtures are written in UTC+7 (the zone of the lab Macs); the helper must give the same answer whatever the zone is.
let securityTestZone = TimeZone(secondsFromGMT: 7 * 3600)!

func securityEpoch(_ iso: String) -> Int {
    Int(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970)
}

/// One compact log line as `log show --style compact` writes it.
func sshLine(_ local: String, pid: Int, process: String = "sshd-session", message: String = "(libsystem_info.dylib) Retrieve User by Name") -> String {
    "\(local).123 A  \(process)[\(pid):1e2217] \(message)"
}

final class SshConnectionLogTests: XCTestCase {
    func testOnlyTimestampedSshdSessionLinesAreRead() {
        let text = """
        Timestamp               Ty Process[PID:TID]
        \(sshLine("2026-11-01 14:23:06", pid: 68225))
        \(sshLine("2026-11-01 14:23:07", pid: 68226, process: "sshd"))
        \(sshLine("2026-11-01 14:23:08", pid: 68227, process: "sshd-auth"))
        Filtering the log data using "process == sshd-session"
        2026-11-01 14:23:09.5 E  sshd-session[abc:1e] bad pid
        2026-11-31 99:23:09.500 E  sshd-session[5:1e] impossible time
        not a log line at all
        \(sshLine("2026-11-01 14:23:10", pid: 68225, message: "Failed password for root from 1.2.3.4 port 22"))
        """
        let found = SshConnectionLog.parse(text, zone: securityTestZone)
        XCTAssertEqual(found, [SshSighting(epoch: securityEpoch("2026-11-01T07:23:06Z"), pid: 68225), SshSighting(epoch: securityEpoch("2026-11-01T07:23:10Z"), pid: 68225)])
    }

    func testEmptyTextGivesNothing() {
        XCTAssertEqual(SshConnectionLog.parse("", zone: securityTestZone), [])
        XCTAssertEqual(SshConnectionLog.parse("\n\n", zone: securityTestZone), [])
    }

    func testTheZoneDecidesTheUnixTime() {
        let line = sshLine("2026-11-01 14:23:06", pid: 1)
        XCTAssertEqual(SshConnectionLog.parse(line, zone: TimeZone(secondsFromGMT: 0)!).first?.epoch, securityEpoch("2026-11-01T14:23:06Z"))
        XCTAssertEqual(SshConnectionLog.parse(line, zone: TimeZone(secondsFromGMT: -5 * 3600)!).first?.epoch, securityEpoch("2026-11-01T19:23:06Z"))
    }
}

final class ConnectionCounterTests: XCTestCase {
    private func seen(_ iso: String, _ pid: Int) -> SshSighting { SshSighting(epoch: securityEpoch(iso), pid: pid) }

    func testEachProcessCountsOnceInTheHourItFirstAppears() {
        var counter = ConnectionCounter()
        let hours = counter.count([seen("2026-11-01T07:10:00Z", 10), seen("2026-11-01T07:10:01Z", 10), seen("2026-11-01T07:50:00Z", 11),
                                   seen("2026-11-01T08:05:00Z", 12), seen("2026-11-01T07:59:00Z", 10), seen("2026-11-01T09:30:00Z", 13), seen("2026-11-01T09:31:00Z", 14)])
        XCTAssertEqual(hours.map(\.connections), [2, 1, 2])
        XCTAssertEqual(hours.map(\.hourStart), [securityEpoch("2026-11-01T07:00:00Z"), securityEpoch("2026-11-01T08:00:00Z"), securityEpoch("2026-11-01T09:00:00Z")])
        XCTAssertEqual(hours.map(\.lastEpoch), [securityEpoch("2026-11-01T07:50:00Z"), securityEpoch("2026-11-01T08:05:00Z"), securityEpoch("2026-11-01T09:31:00Z")])
    }

    func testALongSessionLoggingAgainLaterIsNotANewConnection() {
        var counter = ConnectionCounter()
        XCTAssertEqual(counter.count([seen("2026-11-01T07:10:00Z", 10)]).map(\.connections), [1])
        XCTAssertEqual(counter.count([seen("2026-11-01T11:00:00Z", 10)]), [], "the same process id four hours later is the same session ending")
    }

    func testAProcessIdUsedAgainAfterADayIsANewConnection() {
        var counter = ConnectionCounter()
        _ = counter.count([seen("2026-11-01T07:10:00Z", 10)])
        let later = counter.count([seen("2026-11-02T08:11:00Z", 10)])
        XCTAssertEqual(later.map(\.connections), [1])
    }

    func testNothingInNothingOut() {
        var counter = ConnectionCounter()
        XCTAssertEqual(counter.count([]), [])
    }

    func testTheMemoryForgetsProcessesThatAreOldEnough() {
        var counter = ConnectionCounter()
        _ = counter.count([seen("2026-11-01T00:00:00Z", 1), seen("2026-11-03T00:00:00Z", 2)])
        XCTAssertEqual(counter, { var other = ConnectionCounter(); _ = other.count([SshSighting(epoch: securityEpoch("2026-11-03T00:00:00Z"), pid: 2)]); return other }())
    }
}

final class SecurityCursorTests: XCTestCase {
    func testACursorSurvivesARoundTrip() {
        XCTAssertEqual(SecurityCursor.encode(1_793_520_000), "m1.1793520000")
        XCTAssertEqual(SecurityCursor.decode("m1.1793520000"), 1_793_520_000)
        XCTAssertEqual(SecurityCursor.decode("m1.0"), 0)
    }

    func testAnythingGarbledIsRefused() {
        let bad = ["", "m1.", "m1", "m2.5", "m1.-5", "m1.+5", "m1.5.6", "m1. 5", "m1.5x", "m1.99999999999999", "v1.a-x.f-x", "<script>", "../../etc/passwd", "m1.١٢٣"]
        for text in bad { XCTAssertNil(SecurityCursor.decode(text), text) }
    }

    func testTheQueryAcceptsOneToTwoThousandAndDefaultsTo500() throws {
        XCTAssertEqual(try SecurityQuery.parse(after: [], limit: []), SecurityQuery(after: nil, limit: 500))
        XCTAssertEqual(try SecurityQuery.parse(after: ["m1.5"], limit: ["1"]), SecurityQuery(after: "m1.5", limit: 1))
        XCTAssertEqual(try SecurityQuery.parse(after: [""], limit: ["2000"]), SecurityQuery(after: nil, limit: 2000))
    }

    func testTheQueryRefusesWhatIsOutOfBounds() {
        for limit in ["0", "-1", "2001", "abc", "", "1.5", "99999999999999999999"] {
            XCTAssertThrowsError(try SecurityQuery.parse(after: [], limit: [limit]), limit) { XCTAssertTrue($0 is InputError) }
        }
        XCTAssertThrowsError(try SecurityQuery.parse(after: ["a", "b"], limit: []))
        XCTAssertThrowsError(try SecurityQuery.parse(after: [], limit: ["1", "2"]))
    }
}
