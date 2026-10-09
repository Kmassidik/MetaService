import XCTest
import RootCore
@testable import RootStore

final class StoreTests: XCTestCase {
    private var database: Database!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
    }

    private func heartbeat(_ change: ((inout [String: Any]) -> Void)? = nil) throws -> HeartbeatRequest {
        var body: [String: Any] = [
            "facts": ["os": "macos", "arch": "arm64", "cpu_cores": 10, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 50000,
                      "free_disk_gb": 800, "gpu": [], "capabilities": ["vm": true, "container": false, "gpu_in_vm": false, "gpu_in_container": false]],
            "workloads": [["id": "wl-1", "name": "demo", "kind": "vm", "state": "running", "cpu": 2, "ram_mb": 4096, "disk_gb": 50, "gpu_mode": "none"]],
        ]
        change?(&body)
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: body))
    }

    func testMigrationsRunOnceAndKeepData() throws {
        try MachineStore(database).enroll(name: "a", tokenHash: "h1", commandTokenSealed: "sealed", ip: nil, now: now)
        try Migrations.migrate(database)
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM machines").first?.int("n"), 1)
        XCTAssertEqual(try database.query("SELECT MAX(version) AS v FROM schema_version").first?.int("v"), Migrations.latest)
    }

    func testAuditLogIsAppendOnly() throws {
        let audit = AuditStore(database)
        try audit.record(actor: "kurnia", action: "test", target: "x", detail: ["k": "v"], at: now)
        XCTAssertThrowsError(try database.execute("UPDATE audit_log SET actor = 'evil'"))
        XCTAssertThrowsError(try database.execute("DELETE FROM audit_log"))
        let entries = try audit.list(limit: 10, before: nil)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].actor, "kurnia")
    }

    func testAuditPaging() throws {
        let audit = AuditStore(database)
        for index in 0..<5 { try audit.record(actor: "a", action: "n\(index)", at: now) }
        let page = try audit.list(limit: 2, before: nil)
        XCTAssertEqual(page.map(\.action), ["n4", "n3"])
        XCTAssertEqual(try audit.list(limit: 2, before: page.last!.id).map(\.action), ["n2", "n1"])
        XCTAssertEqual(try audit.list(limit: 10_000, before: nil).count, 5)
    }

    func testEnrollmentTokenWorksOnceForTheRightName() throws {
        let store = EnrollmentStore(database)
        let made = try store.create(machineName: "dgx", now: now)
        XCTAssertFalse(try store.consume(token: made.token, machineName: "other", now: now))
        XCTAssertFalse(try store.consume(token: "nope-nope-nope-nope", machineName: "dgx", now: now))
        XCTAssertTrue(try store.consume(token: made.token, machineName: "dgx", now: now))
        XCTAssertFalse(try store.consume(token: made.token, machineName: "dgx", now: now))
    }

    func testEnrollmentTokenExpires() throws {
        let store = EnrollmentStore(database)
        let made = try store.create(machineName: "dgx", now: now)
        XCTAssertFalse(try store.consume(token: made.token, machineName: "dgx", now: now.addingTimeInterval(EnrollmentStore.lifetime + 1)))
    }

    func testEnrollmentStoresOnlyAHash() throws {
        let made = try EnrollmentStore(database).create(machineName: "dgx", now: now)
        let stored = try database.query("SELECT token_hash FROM enrollments").first?.string("token_hash")
        XCTAssertNotEqual(stored, made.token)
        XCTAssertEqual(stored, Tokens.sha256Hex(made.token))
    }

    func testCannotInviteAnExistingMachine() throws {
        try MachineStore(database).enroll(name: "dgx", tokenHash: "h", commandTokenSealed: "sealed", ip: nil, now: now)
        XCTAssertThrowsError(try EnrollmentStore(database).create(machineName: "dgx", now: now)) { XCTAssertEqual($0 as? EnrollmentError, .machineExists) }
    }

    func testMachineEnrollAuthenticateRemove() throws {
        let machines = MachineStore(database)
        try machines.enroll(name: "mini", tokenHash: "hash-1", commandTokenSealed: "sealed", ip: "10.0.0.5", now: now)
        XCTAssertThrowsError(try machines.enroll(name: "mini", tokenHash: "hash-2", commandTokenSealed: "sealed", ip: nil, now: now)) { XCTAssertEqual($0 as? MachineError, .exists) }
        XCTAssertEqual(try machines.authenticate(tokenHash: "hash-1"), "mini")
        XCTAssertNil(try machines.authenticate(tokenHash: "hash-x"))
        try machines.remove(id: "mini")
        XCTAssertNil(try machines.authenticate(tokenHash: "hash-1"))
        XCTAssertThrowsError(try machines.remove(id: "mini")) { XCTAssertEqual($0 as? MachineError, .notFound) }
    }

    func testHeartbeatStoresFactsAndReplacesWorkloads() throws {
        let machines = MachineStore(database)
        try machines.enroll(name: "mini", tokenHash: "h", commandTokenSealed: "sealed", ip: nil, now: now)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(), ip: "192.0.2.7", now: now)
        var seen = try machines.get(id: "mini", now: now)
        XCTAssertEqual(seen.state, "online")
        XCTAssertEqual(seen.os, "macos")
        XCTAssertEqual(seen.ip, "192.0.2.7")
        XCTAssertEqual(seen.workloads.map(\.id), ["wl-1"])
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat { $0["workloads"] = [] }, ip: nil, now: now)
        seen = try machines.get(id: "mini", now: now)
        XCTAssertTrue(seen.workloads.isEmpty)
        XCTAssertEqual(seen.ip, "192.0.2.7", "a heartbeat without an address keeps the old one")
    }

    func testStateTurnsOfflineAndBusy() throws {
        let machines = MachineStore(database)
        try machines.enroll(name: "mini", tokenHash: "h", commandTokenSealed: "sealed", ip: nil, now: now)
        XCTAssertEqual(try machines.get(id: "mini", now: now).state, "offline", "never seen")
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(), ip: nil, now: now)
        XCTAssertEqual(try machines.get(id: "mini", now: now.addingTimeInterval(30)).state, "online")
        XCTAssertEqual(try machines.get(id: "mini", now: now.addingTimeInterval(50)).state, "offline")
        let busy = try heartbeat { $0["workloads"] = [["id": "wl-2", "name": "x", "kind": "vm", "state": "provisioning", "cpu": 1, "ram_mb": 512, "disk_gb": 1, "gpu_mode": "none"]] }
        try machines.recordHeartbeat(machineId: "mini", request: busy, ip: nil, now: now)
        XCTAssertEqual(try machines.get(id: "mini", now: now).state, "busy")
    }

    func testHostileTextIsStoredAsTextAndTablesSurvive() throws {
        let machines = MachineStore(database)
        let hostile = "x'; DROP TABLE machines; --"
        try machines.enroll(name: "mini", tokenHash: hostile, commandTokenSealed: "sealed", ip: hostile, now: now)
        XCTAssertEqual(try machines.authenticate(tokenHash: hostile), "mini")
        XCTAssertEqual(try machines.get(id: "mini", now: now).ip, hostile)
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM machines").first?.int("n"), 1)
    }

    func testRemovingAMachineRemovesItsWorkloads() throws {
        let machines = MachineStore(database)
        try machines.enroll(name: "mini", tokenHash: "h", commandTokenSealed: "sealed", ip: nil, now: now)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(), ip: nil, now: now)
        try machines.remove(id: "mini")
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM workloads").first?.int("n"), 0)
    }

    func testSessions() throws {
        let sessions = SessionStore(database)
        let made = try sessions.create(username: "admin", now: now)
        XCTAssertEqual(try sessions.lookup(token: made.token, now: now)?.username, "admin")
        XCTAssertEqual(try sessions.lookup(token: made.token, now: now)?.csrfToken, made.csrf)
        XCTAssertNil(try sessions.lookup(token: "wrong", now: now))
        XCTAssertNil(try sessions.lookup(token: made.token, now: now.addingTimeInterval(SessionStore.lifetime + 1)))
        try sessions.delete(token: made.token)
        XCTAssertNil(try sessions.lookup(token: made.token, now: now))
    }

    func testSessionTokenIsStoredHashed() throws {
        let made = try SessionStore(database).create(username: "admin", now: now)
        XCTAssertNotEqual(try database.query("SELECT token_hash FROM sessions").first?.string("token_hash"), made.token)
    }

    func testTheAdminAccountIsCreatedOnceAndOnlyAHashIsKept() throws {
        let admin = AdminStore(database)
        XCTAssertFalse(admin.isConfigured)
        XCTAssertTrue(try admin.create(username: "admin", password: "a long enough password"))
        XCTAssertTrue(admin.isConfigured)
        XCTAssertFalse(try admin.create(username: "intruder", password: "another password!"), "a second account must never replace the first")
        let record = try XCTUnwrap(try admin.get())
        XCTAssertEqual(record.username, "admin")
        XCTAssertTrue(PasswordHash.matches(password: "a long enough password", salt: record.salt, iterations: record.iterations, expected: record.hash))
        XCTAssertFalse(PasswordHash.matches(password: "another password!", salt: record.salt, iterations: record.iterations, expected: record.hash))
        let stored = try database.query("SELECT salt, hash FROM admin").map { $0.string("salt") + $0.string("hash") }.joined()
        XCTAssertFalse(stored.contains("a long enough password"))
    }
}

final class ScanStoreTests: XCTestCase {
    private var database: Database!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
    }

    private func finding(_ ip: String, mac: String? = nil) -> ScanFinding {
        ScanFinding(ip: ip, mac: mac, hostname: "h-\(ip)", vendor: nil, seenBy: [.router, .nmap], agentPortOpen: false)
    }

    func testOnlyOneRunAtATime() throws {
        let scans = ScanStore(database)
        let first = try scans.start(actor: "k", subnet: "192.168.100.0/24", now: now)
        XCTAssertThrowsError(try scans.start(actor: "k", subnet: "192.168.100.0/24", now: now)) { XCTAssertEqual($0 as? ScanError, .alreadyRunning) }
        try scans.finish(runId: first, findings: [], sources: [:], now: now)
        XCTAssertNoThrow(try scans.start(actor: "k", subnet: "192.168.100.0/24", now: now))
    }

    func testACrashedRunStopsBlockingAfterAWhile() throws {
        let scans = ScanStore(database)
        _ = try scans.start(actor: "k", subnet: "192.168.100.0/24", now: now)
        XCTAssertNoThrow(try scans.start(actor: "k", subnet: "192.168.100.0/24", now: now.addingTimeInterval(ScanStore.staleAfter + 1)))
    }

    func testResultsAreStoredSortedAndMarkedManaged() throws {
        let scans = ScanStore(database)
        try MachineStore(database).enroll(name: "mini", tokenHash: "h", commandTokenSealed: "sealed", ip: "192.168.100.9", now: now)
        let id = try scans.start(actor: "k", subnet: "192.168.100.0/24", now: now)
        try scans.finish(runId: id, findings: [finding("192.168.100.40", mac: "AA:BB:CC:00:00:40"), finding("192.168.100.9")], sources: ["router": "ok", "nmap": "ok"], now: now)
        let run = try XCTUnwrap(try scans.latest())
        XCTAssertEqual(run.state, "done")
        XCTAssertEqual(run.sources, ["router": "ok", "nmap": "ok"])
        XCTAssertEqual(run.results.map(\.ip), ["192.168.100.9", "192.168.100.40"])
        XCTAssertEqual(run.results[0].machine, "mini")
        XCTAssertNil(run.results[1].machine)
        XCTAssertEqual(run.results[1].seenBy, ["router", "nmap"])
        XCTAssertEqual(try scans.result(runId: id, resultId: run.results[1].id).ip, "192.168.100.40")
        XCTAssertThrowsError(try scans.result(runId: id, resultId: 9999))
    }

    func testFailedRunsAndOldRunsArePruned() throws {
        let scans = ScanStore(database)
        let id = try scans.start(actor: "k", subnet: "192.168.100.0/24", now: now)
        try scans.fail(runId: id, sources: ["nmap": "missing"], now: now)
        XCTAssertEqual(try scans.get(id: id).state, "failed")
        for _ in 0..<(ScanStore.keepRuns + 3) {
            let next = try scans.start(actor: "k", subnet: "192.168.100.0/24", now: now)
            try scans.finish(runId: next, findings: [finding("192.168.100.5")], sources: [:], now: now)
        }
        XCTAssertThrowsError(try scans.get(id: id)) { XCTAssertEqual($0 as? ScanError, .notFound) }
        XCTAssertLessThanOrEqual(try database.query("SELECT COUNT(*) AS n FROM scan_runs").first?.int("n") ?? 99, ScanStore.keepRuns + 1)
        XCTAssertLessThanOrEqual(try database.query("SELECT COUNT(*) AS n FROM scan_results").first?.int("n") ?? 99, ScanStore.keepRuns + 1)
    }

    func testHostileDeviceNamesAreStoredAsText() throws {
        let scans = ScanStore(database)
        let id = try scans.start(actor: "k", subnet: "192.168.100.0/24", now: now)
        let hostile = ScanFinding(ip: "192.168.100.5", mac: nil, hostname: "x'; DROP TABLE machines;--<script>", vendor: nil, seenBy: [.nmap], agentPortOpen: false)
        try scans.finish(runId: id, findings: [hostile], sources: [:], now: now)
        XCTAssertEqual(try scans.latest()?.results.first?.hostname, "x'; DROP TABLE machines;--<script>")
        XCTAssertNoThrow(try database.query("SELECT COUNT(*) FROM machines"))
    }
}
