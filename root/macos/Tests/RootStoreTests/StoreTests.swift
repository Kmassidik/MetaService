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
        try MachineStore(database).enroll(name: "a", tokenHash: "h1", ip: nil, now: now)
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
        try MachineStore(database).enroll(name: "dgx", tokenHash: "h", ip: nil, now: now)
        XCTAssertThrowsError(try EnrollmentStore(database).create(machineName: "dgx", now: now)) { XCTAssertEqual($0 as? EnrollmentError, .machineExists) }
    }

    func testMachineEnrollAuthenticateRemove() throws {
        let machines = MachineStore(database)
        try machines.enroll(name: "mini", tokenHash: "hash-1", ip: "10.0.0.5", now: now)
        XCTAssertThrowsError(try machines.enroll(name: "mini", tokenHash: "hash-2", ip: nil, now: now)) { XCTAssertEqual($0 as? MachineError, .exists) }
        XCTAssertEqual(try machines.authenticate(tokenHash: "hash-1"), "mini")
        XCTAssertNil(try machines.authenticate(tokenHash: "hash-x"))
        try machines.remove(id: "mini")
        XCTAssertNil(try machines.authenticate(tokenHash: "hash-1"))
        XCTAssertThrowsError(try machines.remove(id: "mini")) { XCTAssertEqual($0 as? MachineError, .notFound) }
    }

    func testHeartbeatStoresFactsAndReplacesWorkloads() throws {
        let machines = MachineStore(database)
        try machines.enroll(name: "mini", tokenHash: "h", ip: nil, now: now)
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
        try machines.enroll(name: "mini", tokenHash: "h", ip: nil, now: now)
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
        try machines.enroll(name: "mini", tokenHash: hostile, ip: hostile, now: now)
        XCTAssertEqual(try machines.authenticate(tokenHash: hostile), "mini")
        XCTAssertEqual(try machines.get(id: "mini", now: now).ip, hostile)
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM machines").first?.int("n"), 1)
    }

    func testRemovingAMachineRemovesItsWorkloads() throws {
        let machines = MachineStore(database)
        try machines.enroll(name: "mini", tokenHash: "h", ip: nil, now: now)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(), ip: nil, now: now)
        try machines.remove(id: "mini")
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM workloads").first?.int("n"), 0)
    }

    func testSessions() throws {
        let sessions = SessionStore(database)
        let made = try sessions.create(email: "k@example.com", now: now)
        XCTAssertEqual(try sessions.lookup(token: made.token, now: now)?.email, "k@example.com")
        XCTAssertEqual(try sessions.lookup(token: made.token, now: now)?.csrfToken, made.csrf)
        XCTAssertNil(try sessions.lookup(token: "wrong", now: now))
        XCTAssertNil(try sessions.lookup(token: made.token, now: now.addingTimeInterval(SessionStore.lifetime + 1)))
        try sessions.delete(token: made.token)
        XCTAssertNil(try sessions.lookup(token: made.token, now: now))
        let stored = try database.query("SELECT token_hash FROM sessions").count
        XCTAssertEqual(stored, 0)
    }

    func testSessionTokenIsStoredHashed() throws {
        let made = try SessionStore(database).create(email: "k@example.com", now: now)
        let stored = try database.query("SELECT token_hash FROM sessions").first?.string("token_hash")
        XCTAssertNotEqual(stored, made.token)
    }
}
