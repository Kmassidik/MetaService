import XCTest
@testable import RootCore

final class SecurityTextTests: XCTestCase {
    func testControlCharactersAndRunsOfSpacesAreCleaned() {
        XCTAssertEqual(SecurityText.user("  ro\u{0007}ot \n\t admin\u{001b}[31m  "), "ro ot admin [31m")
        XCTAssertNil(SecurityText.user(" \n\u{0000} "))
        XCTAssertNil(SecurityText.user(nil))
    }

    func testTextIsCutToItsLimit() {
        XCTAssertEqual(SecurityText.user(String(repeating: "a", count: 200))?.count, SecurityText.maxUser)
        XCTAssertEqual(SecurityText.detail(String(repeating: "b", count: 500))?.count, SecurityText.maxDetail)
    }

    func testAHostileUserNameStaysPlainText() {
        XCTAssertEqual(SecurityText.user("<script>x</script>"), "<script>x</script>")
    }

    func testOnlyAddressesAndHostNamesSurvive() {
        XCTAssertEqual(SecurityText.address("45.13.2.9"), "45.13.2.9")
        XCTAssertEqual(SecurityText.address("2001:db8::1"), "2001:db8::1")
        XCTAssertEqual(SecurityText.address("bot.example.com"), "bot.example.com")
        XCTAssertNil(SecurityText.address("999.1.1.1"))
        XCTAssertNil(SecurityText.address("<script>x</script>"))
        XCTAssertNil(SecurityText.address("a b"))
        XCTAssertNil(SecurityText.address("-bad.example.com"))
        XCTAssertNil(SecurityText.address("12:34"))
        XCTAssertNil(SecurityText.address(String(repeating: "a", count: 65)))
        XCTAssertNil(SecurityText.address(""))
    }
}

final class SecurityTimeAndRangeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_523_000) // 2026-11-01T08:50:00Z

    func testTimesAreUtcTextWithSeconds() {
        XCTAssertEqual(SecurityTime.text(now), "2026-11-01T08:50:00Z")
        XCTAssertEqual(SecurityTime.day(now), "2026-11-01")
        XCTAssertEqual(SecurityTime.parse("2026-11-01T10:50:00+02:00"), now)
        XCTAssertEqual(SecurityTime.parse("2026-11-01T08:50:00.250Z")?.timeIntervalSince(now) ?? 0, 0.25, accuracy: 0.001)
        XCTAssertNil(SecurityTime.parse("yesterday"))
    }

    func testATimeFarInTheFutureBecomesNow() {
        XCTAssertEqual(SecurityTime.normalized("2099-01-01T00:00:00Z", now: now), now)
        XCTAssertEqual(SecurityTime.normalized("2026-11-01T09:00:00Z", now: now), SecurityTime.parse("2026-11-01T09:00:00Z"))
    }

    func testRangesReachBackToTheirFirstDay() {
        XCTAssertEqual(SecurityRange.day.firstDay(now: now), "2026-10-31")
        XCTAssertEqual(SecurityRange.week.firstDay(now: now), "2026-10-25")
        XCTAssertEqual(SecurityRange.month.firstDay(now: now), "2026-10-02")
        XCTAssertEqual(SecurityRange.quarter.firstDay(now: now), "2026-08-03")
        XCTAssertEqual(SecurityRange(rawValue: "7d"), .week)
        XCTAssertNil(SecurityRange(rawValue: "1y"))
    }

    func testTheShortRangesAreAcceptedAndOthersStayRefused() throws {
        for name in ["1h", "6h", "12h"] {
            XCTAssertEqual(try SecurityQuery.overview([("range", name)]).rawValue, name)
            XCTAssertEqual(try SecurityQuery.events([("range", name)]).range.rawValue, name)
        }
        XCTAssertEqual(SecurityRange.sixHours.seconds, 6 * 3_600)
        for bad in ["2h", "48h", "1H", "0h"] { XCTAssertThrowsError(try SecurityQuery.overview([("range", bad)]), bad) }
    }

    func testRetentionIsNinetyDaysAndRunsEverySixHours() {
        XCTAssertEqual(SecurityTime.day(SecurityTime.retentionCutoff(now: now)), "2026-08-03")
        XCTAssertTrue(SecurityTime.retentionDue(lastRun: nil, now: now))
        XCTAssertFalse(SecurityTime.retentionDue(lastRun: now.addingTimeInterval(-3_600), now: now))
        XCTAssertTrue(SecurityTime.retentionDue(lastRun: now.addingTimeInterval(-6 * 3_600), now: now))
    }
}

final class SecurityQueryTests: XCTestCase {
    private func events(_ pairs: [(String, String)]) throws -> SecurityQuery { try SecurityQuery.events(pairs) }

    func testDefaults() throws {
        let query = try events([])
        XCTAssertEqual(query.range, .week)
        XCTAssertEqual(query.page, 1)
        XCTAssertEqual(query.pageSize, 25)
        XCTAssertEqual(query.offset, 0)
    }

    func testEveryFieldIsRead() throws {
        let query = try events([("range", "30d"), ("machine", "rtx-pc"), ("type", "blocked"), ("q", "  45.1 "), ("page", "3"), ("page_size", "100")])
        XCTAssertEqual(query.range, .month)
        XCTAssertEqual(query.machine, "rtx-pc")
        XCTAssertEqual(query.type, .blocked)
        XCTAssertEqual(query.text, "45.1")
        XCTAssertEqual(query.offset, 200)
    }

    func testBadValuesAreRefused() {
        let bad: [[(String, String)]] = [
            [("range", "1y")], [("range", "")], [("machine", "Bad Id")], [("machine", "")], [("type", "nope")], [("page", "0")], [("page", "05")], [("page", "+5")],
            [("page", "-1")], [("page_size", "101")], [("page_size", "0")], [("page_size", "2.5")], [("q", String(repeating: "a", count: 65))], [("q", "a\u{0001}b")],
            [("sort", "time")], [("page", "1"), ("page", "2")],
        ]
        for pairs in bad {
            XCTAssertThrowsError(try events(pairs), "\(pairs)") { XCTAssertTrue($0 is SecurityQuery.Refused) }
        }
    }

    func testTheOverviewTakesOnlyARange() throws {
        XCTAssertEqual(try SecurityQuery.overview([]), .week)
        XCTAssertEqual(try SecurityQuery.overview([("range", "24h")]), .day)
        XCTAssertThrowsError(try SecurityQuery.overview([("machine", "a")]))
        XCTAssertThrowsError(try SecurityQuery.overview([("range", "9d")]))
    }
}

final class SecurityPullParseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_523_000)

    private func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    private func failed(_ extra: [String: Any] = [:]) -> [String: Any] {
        ["time": "2026-11-01T08:00:00Z", "type": "failed_login", "user": "root", "address": "45.1.1.1", "count": 3].merging(extra) { $1 }
    }

    func testAGoodAnswerIsRead() throws {
        let pull = try SecurityPull.parse(data(["cursor": "c1", "reset": true, "events": [failed(), ["time": "2026-11-01T08:10:00Z", "type": "blocked", "address": "45.1.1.1", "until": "2026-11-01T09:00:00Z"]],
                                                "baseline": ["password_login": true, "ban_tool": "running", "pending_updates": 4]]), limit: 500, now: now)
        XCTAssertEqual(pull.cursor, "c1")
        XCTAssertTrue(pull.reset)
        XCTAssertEqual(pull.events.map(\.type), [.failedLogin, .blocked])
        XCTAssertEqual(pull.events[0].count, 3)
        XCTAssertNotNil(pull.events[1].until)
        XCTAssertEqual(pull.baseline, SecurityBaseline(passwordLogin: true, banTool: "running", pendingUpdates: 4))
        XCTAssertEqual(pull.received, 2)
    }

    func testEventsThatCannotBeReadAreLeftOutAndCounted() throws {
        let pull = try SecurityPull.parse(data(["cursor": "c", "events": [failed(["type": "other"]), failed(["time": "never"]), failed(["count": 0]), failed(["count": "3"]), "text", failed()]]), limit: 500, now: now)
        XCTAssertEqual(pull.events.count, 1)
        XCTAssertEqual(pull.dropped, 5)
        XCTAssertEqual(pull.received, 6)
    }

    func testOtherTypesCountOnceAndCleanTheirText() throws {
        let pull = try SecurityPull.parse(data(["cursor": "c", "events": [["time": "2026-11-01T08:00:00Z", "type": "login", "user": "kurnia\n", "address": "<b>", "method": "magic", "count": 50, "until": "2026-11-01T09:00:00Z"]]]), limit: 5, now: now)
        let login = try XCTUnwrap(pull.events.first)
        XCTAssertEqual(login.count, 1)
        XCTAssertEqual(login.user, "kurnia")
        XCTAssertNil(login.address)
        XCTAssertNil(login.method)
        XCTAssertNil(login.until)
    }

    func testABrokenAnswerIsRefused() {
        XCTAssertThrowsError(try SecurityPull.parse(Data("nope".utf8), limit: 5, now: now))
        XCTAssertThrowsError(try SecurityPull.parse(data(["events": []]), limit: 5, now: now))
        XCTAssertThrowsError(try SecurityPull.parse(data(["cursor": "", "events": []]), limit: 5, now: now))
        XCTAssertThrowsError(try SecurityPull.parse(data(["cursor": "a\nb", "events": []]), limit: 5, now: now))
        XCTAssertThrowsError(try SecurityPull.parse(data(["cursor": "c"]), limit: 5, now: now))
        XCTAssertThrowsError(try SecurityPull.parse(data(["cursor": "c", "events": [failed(), failed()]]), limit: 1, now: now))
    }

    func testTheBaselineKeepsUnknownAsUnknown() {
        let baseline = SecurityBaseline(helper: ["password_login": "yes", "ban_tool": "magic", "firewall": 1, "auto_updates": false, "pending_updates": -2])
        XCTAssertNil(baseline.passwordLogin)
        XCTAssertNil(baseline.banTool)
        XCTAssertNil(baseline.firewall)
        XCTAssertEqual(baseline.autoUpdates, false)
        XCTAssertNil(baseline.pendingUpdates)
        XCTAssertEqual(SecurityBaseline(helper: nil), .unknown)
    }

    func testTheBaselineIsWrittenWithEveryKey() throws {
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(SecurityBaseline.unknown), encoding: .utf8))
        for key in ["password_login", "ban_tool", "firewall", "auto_updates", "starts_after_reboot", "pending_updates"] { XCTAssertTrue(json.contains("\"\(key)\":null"), key) }
    }
}

final class SecurityCapabilityTests: XCTestCase {
    private func heartbeat(capabilities: [String: Any] = [:]) throws -> HeartbeatRequest {
        var caps: [String: Any] = ["vm": false, "container": true, "gpu_in_vm": false, "gpu_in_container": false]
        caps.merge(capabilities) { $1 }
        let facts: [String: Any] = ["os": "linux", "arch": "x86_64", "cpu_cores": 8, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 60000, "free_disk_gb": 900, "gpu": [], "capabilities": caps]
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: ["facts": facts, "workloads": []]))
    }

    func testTheHelperSaysSecurityAndOldHelpersReadAsNotSaying() throws {
        XCTAssertTrue(try heartbeat(capabilities: ["security": true]).facts.capabilities.security)
        XCTAssertFalse(try heartbeat(capabilities: ["security": false]).facts.capabilities.security)
        XCTAssertFalse(try heartbeat().facts.capabilities.security)
        XCTAssertThrowsError(try heartbeat(capabilities: ["security": "yes"]))
    }

    func testSecuritySurvivesSavingAndTheGpuLimit() throws {
        let saved = Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false, security: true)
        XCTAssertTrue(try JSONDecoder().decode(Capabilities.self, from: JSONEncoder().encode(saved)).security)
        XCTAssertTrue(MachineSettings(allowGpu: false).limiting(saved)?.security == true)
        let old = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"vm":true,"container":true,"gpuInVm":false,"gpuInContainer":false}"#.utf8))
        XCTAssertFalse(old.security)
    }
}
