import XCTest
import RootCore
@testable import RootStore

final class VmOriginStoreTests: XCTestCase {
    private var database: Database!
    private var origins: VmOriginStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let mcp = VmOriginInput(kind: .mcp, actor: "mcp:Ayu", personId: "mp-1", personName: "Ayu", tokenId: "mt-1", tokenPrefix: "AbCdEfGh", clientName: "claude-code",
                                    clientVersion: "2.0.1", sourceIp: "203.0.113.9", requestId: "mr-1")

    private func store(key: String = "k1") -> VmOriginStore {
        VmOriginStore(database) { Tokens.sha256Hex(key + "|" + $0) }
    }

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        origins = store()
    }

    func testARecordIsReadBackWithEveryFieldAndAVerifiedSeal() throws {
        try origins.record(machine: "mini", workload: "vm-1", input: mcp, createdAt: 1_799_999_000)
        let read = try XCTUnwrap(try origins.get(machine: "mini", workload: "vm-1"))
        XCTAssertEqual(read.record.input, mcp)
        XCTAssertEqual(read.record.createdAt, 1_799_999_000)
        XCTAssertFalse(read.record.backfilled)
        XCTAssertTrue(read.intact)
        XCTAssertEqual(read.createdBy.label, "Ayu (MCP)")
        XCTAssertNil(try origins.get(machine: "mini", workload: "vm-other"))
    }

    func testAnotherKeyReadsTheRecordAsAltered() throws {
        try origins.record(machine: "mini", workload: "vm-1", input: mcp, createdAt: 1)
        XCTAssertEqual(try store(key: "other").get(machine: "mini", workload: "vm-1")?.intact, false)
    }

    func testTheDatabaseRefusesToEditOrDeleteARecord() throws {
        try origins.record(machine: "mini", workload: "vm-1", input: mcp, createdAt: 1)
        XCTAssertThrowsError(try database.execute("UPDATE vm_origin SET actor = 'mcp:Mallory'"))
        XCTAssertThrowsError(try database.execute("UPDATE vm_origin SET seal = 'aaaaaaaaaaaaaaaa'"))
        XCTAssertThrowsError(try database.execute("UPDATE vm_origin SET backfilled = 1"))
        XCTAssertThrowsError(try database.execute("DELETE FROM vm_origin"))
        XCTAssertEqual(try origins.get(machine: "mini", workload: "vm-1")?.record.input.actor, "mcp:Ayu")
    }

    func testDeletionIsNotedOnceWithWhoDidIt() throws {
        try origins.record(machine: "mini", workload: "vm-1", input: mcp, createdAt: 1)
        try origins.markDeleted(machine: "mini", workload: "vm-1", by: "mcp:Ayu", now: now)
        try origins.markDeleted(machine: "mini", workload: "vm-1", by: "mcp:Mallory", now: now.addingTimeInterval(5))
        let read = try XCTUnwrap(try origins.get(machine: "mini", workload: "vm-1"))
        XCTAssertEqual(read.record.deletedBy, "mcp:Ayu")
        XCTAssertEqual(read.record.deletedAt, 1_800_000_000)
        XCTAssertTrue(read.intact)
        XCTAssertNoThrow(try origins.markDeleted(machine: "mini", workload: "nobody", by: "x", now: now))
    }

    func testTheShortFormListsEveryVmOfAMachineWithItsOwnCreator() throws {
        try origins.record(machine: "mini", workload: "vm-1", input: mcp, createdAt: 1)
        try origins.record(machine: "mini", workload: "vm-2", input: .panel(operatorName: "kurnia", sourceIp: "127.0.0.1"), createdAt: 2)
        try origins.record(machine: "dgx", workload: "vm-1", input: .panel(operatorName: "luca", sourceIp: nil), createdAt: 3)
        let short = try origins.createdBy(machine: "mini")
        XCTAssertEqual(short.keys.sorted(), ["vm-1", "vm-2"])
        XCTAssertEqual(short["vm-1"]?.label, "Ayu (MCP)")
        XCTAssertEqual(short["vm-2"]?.label, "panel (kurnia)")
    }

    func testTheMachineAnswerCarriesCreatedByOnEveryWorkload() throws {
        let machines = MachineStore(database, origins: origins)
        try machines.enroll(name: "mini", tokenHash: "h", commandTokenSealed: "s", ip: nil, now: now)
        try database.execute("""
            INSERT INTO workloads (id, machine_id, name, kind, state, cpu, ram_mb, disk_gb, gpu_mode, updated_at) VALUES ('vm-1', 'mini', 'a', 'vm', 'running', 1, 512, 1, 'none', 1), ('vm-2', 'mini', 'b', 'vm', 'running', 1, 512, 1, 'none', 1)
            """)
        try origins.record(machine: "mini", workload: "vm-1", input: mcp, createdAt: 1)
        let found = try machines.get(id: "mini", now: now).workloads
        XCTAssertEqual(found.first { $0.id == "vm-1" }?.createdBy?.label, "Ayu (MCP)")
        XCTAssertEqual(found.first { $0.id == "vm-2" }?.createdBy, .unknown)
        XCTAssertNil(try MachineStore(database).get(id: "mini", now: now).workloads.first?.createdBy)
    }

    // MARK: the one-time backfill

    private func twoOldVms() throws {
        try MachineStore(database).enroll(name: "dgx", tokenHash: "h", commandTokenSealed: "s", ip: nil, now: now)
        try database.execute("""
            INSERT INTO workloads (id, machine_id, name, kind, state, cpu, ram_mb, disk_gb, gpu_mode, updated_at) VALUES ('vm-3e2d', 'dgx', 'a', 'vm', 'running', 1, 512, 1, 'none', 1), ('vm-0019', 'dgx', 'b', 'vm', 'running', 1, 512, 1, 'none', 1)
            """)
    }

    func testTheBackfillRecordsEveryExistingVmAsTheAdminsAndSealsIt() throws {
        try twoOldVms()
        XCTAssertEqual(try origins.backfillOnce(now: now), 2)
        for workload in ["vm-3e2d", "vm-0019"] {
            let read = try XCTUnwrap(try origins.get(machine: "dgx", workload: workload))
            XCTAssertEqual(read.record.input.kind, .panel)
            XCTAssertEqual(read.record.input.actor, "admin")
            XCTAssertTrue(read.record.backfilled)
            XCTAssertNil(read.record.createdAt)
            XCTAssertTrue(read.intact)
            XCTAssertEqual(read.createdBy.label, "admin (recorded afterwards)")
        }
        XCTAssertNotNil(try database.query("SELECT value FROM settings WHERE key = 'vm_origin_backfilled_at'").first)
    }

    func testTheBackfillRunsOnlyOnceSoALaterVmStaysUnknown() throws {
        try twoOldVms()
        try origins.backfillOnce(now: now)
        try database.execute("INSERT INTO workloads (id, machine_id, name, kind, state, cpu, ram_mb, disk_gb, gpu_mode, updated_at) VALUES ('vm-new', 'dgx', 'c', 'vm', 'running', 1, 512, 1, 'none', 1)")
        XCTAssertEqual(try origins.backfillOnce(now: now.addingTimeInterval(60)), 0)
        XCTAssertNil(try origins.get(machine: "dgx", workload: "vm-new"))
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM vm_origin").first?.int("n"), 2)
    }

    func testTheBackfillSkipsAVmThatAlreadyHasARecord() throws {
        try twoOldVms()
        try origins.record(machine: "dgx", workload: "vm-0019", input: mcp, createdAt: 5)
        XCTAssertEqual(try origins.backfillOnce(now: now), 1)
        XCTAssertEqual(try origins.get(machine: "dgx", workload: "vm-0019")?.record.input.kind, .mcp)
    }
}

final class McpMigration30Tests: XCTestCase {
    /// A database as production has it today: migrations up to 29, with tokens that were made then.
    private func databaseAt29() throws -> Database {
        let database = try Database(path: ":memory:")
        try database.exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")
        for step in Migrations.steps where step.version <= 29 {
            try step.apply(database)
            try database.execute("INSERT INTO schema_version (version) VALUES (?)", [.int(step.version)])
        }
        return database
    }

    func testTokensThatExistBecomePeopleWithTheirScopesAndQuotas() throws {
        let database = try databaseAt29()
        try database.execute("""
            INSERT INTO api_tokens (id, name, prefix, token_hash, scopes_json, quotas_json, auto_approve, created_by, created_at, expires_at)
            VALUES ('mt-a', 'claude', 'AAAAAAAA', 'h1', '["read","create"]', '{"max_vms":2}', 1, 'admin', 100, 9000000000),
                   ('mt-b', 'cursor', 'BBBBBBBB', 'h2', '["read"]', '{"max_vms":5}', 0, 'admin', 200, 9000000000),
                   ('mt-c', 'claude', 'CCCCCCCC', 'h3', '["read","create","destroy"]', '{"max_vms":7}', 0, 'admin', 300, 9000000000)
            """)
        try database.execute("INSERT INTO token_workloads (token_id, machine_id, workload_id, request_id, vcpu, ram_mb, disk_gb, created_at) VALUES ('mt-a', 'mini', 'vm-1', 'mr-1', 1, 512, 1, 100)")
        try database.execute("INSERT INTO mcp_requests (id, token_id, kind, params_json, state, idempotency_key, created_at, expires_at) VALUES ('mr-1', 'mt-a', 'create', '{}', 'done', 'k', 100, 200), ('mr-2', 'mt-a', 'delete', '{}', 'pending_approval', NULL, 100, 200)")
        try Migrations.migrate(database)
        let people = McpPeopleStore(database)
        let claude = try XCTUnwrap(try people.find(name: "claude"))
        XCTAssertEqual(claude.id, "mp-mt-c", "a name used twice becomes one person, from the newest token")
        XCTAssertEqual(claude.scopes, [.read, .create, .destroy])
        XCTAssertEqual(claude.quotas.maxVms, 7)
        XCTAssertEqual(try people.find(name: "cursor")?.quotas.maxVms, 5)
        XCTAssertEqual(try people.list().count, 2)
        let tokens = McpTokenStore(database)
        XCTAssertEqual(try tokens.get(id: "mt-a")?.personId, "mp-mt-c")
        XCTAssertEqual(try tokens.get(id: "mt-b")?.personId, "mp-mt-b")
        XCTAssertNotNil(try tokens.find(hash: "h1"), "an existing token still works by its hash")
        XCTAssertEqual(try McpWorkloadStore(database).find(person: "mp-mt-c", machine: "mini", workload: "vm-1")?.tokenId, "mt-a")
        XCTAssertEqual(try McpRequestStore(database).get(id: "mr-1")?.personId, "mp-mt-c")
        XCTAssertEqual(try McpRequestStore(database).find(person: "mp-mt-c", idempotencyKey: "k")?.id, "mr-1")
        let waiting = try XCTUnwrap(try McpRequestStore(database).get(id: "mr-2"))
        XCTAssertEqual(waiting.state, .failed, "a request that waited for approval ends as failed, never run")
        XCTAssertTrue((waiting.result?["message"] as? String)?.contains("Approvals were removed") == true)
        XCTAssertEqual(try database.query("SELECT MAX(version) AS v FROM schema_version").first?.int("v"), Migrations.latest)
    }

    func testMigratingADatabaseWithoutTokensAndAgainIsHarmless() throws {
        let database = try databaseAt29()
        try Migrations.migrate(database)
        try Migrations.migrate(database)
        XCTAssertEqual(try McpPeopleStore(database).list().count, 0)
        XCTAssertEqual(Migrations.latest, 30)
    }
}
