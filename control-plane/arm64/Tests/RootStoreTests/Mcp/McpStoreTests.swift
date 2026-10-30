import XCTest
import RootCore
@testable import RootStore

final class McpStoreTests: XCTestCase {
    private var database: Database!
    private var tokens: McpTokenStore!
    private var workloads: McpWorkloadStore!
    private var requests: McpRequestStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        tokens = McpTokenStore(database)
        workloads = McpWorkloadStore(database)
        requests = McpRequestStore(database)
    }

    private func newToken(_ id: String = "mt-1", name: String = "claude", text: String = "msk_" + String(repeating: "a", count: 43), expires: TimeInterval = 86_400) -> NewMcpToken {
        NewMcpToken(id: id, name: name, prefix: McpToken.displayPrefix(of: text), tokenHash: McpToken.hash(text), scopes: [.read, .create], quotas: .defaults, autoApprove: false,
                    createdBy: "admin", createdAt: now, expiresAt: now.addingTimeInterval(expires))
    }

    private func newRequest(_ id: String, token: String = "mt-1", key: String? = nil, state: McpRequestState = .running) -> NewMcpRequest {
        NewMcpRequest(id: id, tokenId: token, kind: .create, params: ["size": "small"], state: state, idempotencyKey: key, createdAt: now, expiresAt: now.addingTimeInterval(86_400))
    }

    func testMigration29AddsTheThreeTables() throws {
        let names = Set(try database.query("SELECT name FROM sqlite_master WHERE type = 'table'").map { $0.string("name") })
        for table in ["api_tokens", "token_workloads", "mcp_requests"] { XCTAssertTrue(names.contains(table), table) }
    }

    func testATokenIsFoundByItsHashAndTheTextIsNeverStored() throws {
        let text = "msk_" + String(repeating: "q", count: 43)
        try tokens.create(newToken(text: text))
        let found = try XCTUnwrap(try tokens.find(hash: McpToken.hash(text)))
        XCTAssertEqual(found.name, "claude")
        XCTAssertEqual(found.scopes, [.read, .create])
        XCTAssertEqual(found.quotas, .defaults)
        XCTAssertEqual(found.actor, "mcp:claude")
        XCTAssertNil(try tokens.find(hash: McpToken.hash("msk_" + String(repeating: "z", count: 43))))
        let dump = try database.query("SELECT * FROM api_tokens").map { "\($0)" }.joined()
        XCTAssertFalse(dump.contains(text))
    }

    func testRevokedAndExpiredTokensAreRefusedByState() throws {
        try tokens.create(newToken(expires: 100))
        let token = try XCTUnwrap(try tokens.get(id: "mt-1"))
        XCTAssertNil(token.refusal(at: now))
        XCTAssertEqual(token.refusal(at: now.addingTimeInterval(100)), "expired")
        XCTAssertTrue(try tokens.revoke(id: "mt-1", now: now))
        XCTAssertFalse(try tokens.revoke(id: "mt-1", now: now))
        XCTAssertEqual(try tokens.get(id: "mt-1")?.refusal(at: now), "revoked")
    }

    func testLastUsedMovesAtMostOnceAMinute() throws {
        try tokens.create(newToken())
        try tokens.touch(id: "mt-1", now: now)
        try tokens.touch(id: "mt-1", now: now.addingTimeInterval(30))
        XCTAssertEqual(try tokens.get(id: "mt-1")?.lastUsedAt, now)
        try tokens.touch(id: "mt-1", now: now.addingTimeInterval(61))
        XCTAssertEqual(try tokens.get(id: "mt-1")?.lastUsedAt, now.addingTimeInterval(61))
    }

    func testALiveNameIsUniqueButARevokedNameCanBeReused() throws {
        try tokens.create(newToken())
        XCTAssertTrue(try tokens.liveNameExists("claude"))
        try tokens.revoke(id: "mt-1", now: now)
        XCTAssertFalse(try tokens.liveNameExists("claude"))
    }

    func testTheSameHashCannotBeStoredTwice() throws {
        try tokens.create(newToken())
        XCTAssertThrowsError(try tokens.create(newToken("mt-2", name: "other")))
    }

    func testWorkloadsCountTowardTheUsageUntilDeleted() throws {
        try tokens.create(newToken())
        let wish = McpWish(vcpu: 2, ramMb: 4096, diskGb: 40, gpuMemoryGb: nil)
        let first = try workloads.reserve(NewMcpWorkload(tokenId: "mt-1", machineId: "mini", requestId: "mr-1", idempotencyKey: nil, wish: wish, createdAt: now))
        _ = try workloads.reserve(NewMcpWorkload(tokenId: "mt-1", machineId: "mini", requestId: "mr-2", idempotencyKey: nil, wish: wish, createdAt: now))
        XCTAssertEqual(try workloads.usage(token: "mt-1", now: now), McpUsage(aliveVms: 2, vcpu: 4, ramMb: 8192, diskGb: 80, createsLastDay: 2))
        try workloads.markDeleted(row: first, now: now)
        XCTAssertEqual(try workloads.usage(token: "mt-1", now: now), McpUsage(aliveVms: 1, vcpu: 2, ramMb: 4096, diskGb: 40, createsLastDay: 2))
        XCTAssertEqual(try workloads.usage(token: "mt-1", now: now.addingTimeInterval(86_401)).createsLastDay, 0)
    }

    func testARemovedReservationFreesTheSlotAndTheCount() throws {
        try tokens.create(newToken())
        let row = try workloads.reserve(NewMcpWorkload(tokenId: "mt-1", machineId: "mini", requestId: "mr-1", idempotencyKey: nil, wish: McpWish(vcpu: 1, ramMb: 512, diskGb: 1, gpuMemoryGb: nil), createdAt: now))
        try workloads.remove(row: row)
        XCTAssertEqual(try workloads.usage(token: "mt-1", now: now), McpUsage(aliveVms: 0, vcpu: 0, ramMb: 0, diskGb: 0, createsLastDay: 0))
    }

    func testOwnershipIsPerTokenAndNeedsTheVmId() throws {
        try tokens.create(newToken())
        try tokens.create(newToken("mt-2", name: "other", text: "msk_" + String(repeating: "b", count: 43)))
        let row = try workloads.reserve(NewMcpWorkload(tokenId: "mt-1", machineId: "mini", requestId: "mr-1", idempotencyKey: nil, wish: McpWish(vcpu: 1, ramMb: 512, diskGb: 1, gpuMemoryGb: nil), createdAt: now))
        XCTAssertNil(try workloads.find(token: "mt-1", machine: "mini", workload: "wl-1"))
        try workloads.setWorkload(row: row, workload: "wl-1")
        XCTAssertNotNil(try workloads.find(token: "mt-1", machine: "mini", workload: "wl-1"))
        XCTAssertNil(try workloads.find(token: "mt-2", machine: "mini", workload: "wl-1"))
        XCTAssertEqual(try workloads.row(request: "mr-1")?.workloadId, "wl-1")
    }

    func testARepeatedIdempotencyKeyReturnsTheFirstRequest() throws {
        try tokens.create(newToken())
        let first = try requests.create(newRequest("mr-1", key: "k1"))
        let second = try requests.create(newRequest("mr-2", key: "k1"))
        XCTAssertTrue(first.created)
        XCTAssertFalse(second.created)
        XCTAssertEqual(second.request.id, "mr-1")
        XCTAssertNil(try requests.get(id: "mr-2"))
    }

    func testTheSameKeyOfAnotherTokenIsAnotherRequest() throws {
        try tokens.create(newToken())
        try tokens.create(newToken("mt-2", name: "other", text: "msk_" + String(repeating: "b", count: 43)))
        XCTAssertTrue(try requests.create(newRequest("mr-1", key: "k1")).created)
        XCTAssertTrue(try requests.create(newRequest("mr-2", token: "mt-2", key: "k1")).created)
    }

    func testAPendingRequestIsDecidedOnceOnly() throws {
        try tokens.create(newToken())
        _ = try requests.create(newRequest("mr-1", state: .pendingApproval))
        XCTAssertEqual(try requests.pending().map(\.id), ["mr-1"])
        XCTAssertTrue(try requests.decide(id: "mr-1", to: .approved, by: "kurnia", now: now))
        XCTAssertFalse(try requests.decide(id: "mr-1", to: .denied, by: "other", now: now))
        let stored = try XCTUnwrap(try requests.get(id: "mr-1"))
        XCTAssertEqual(stored.state, .approved)
        XCTAssertEqual(stored.decidedBy, "kurnia")
        XCTAssertTrue(try requests.pending().isEmpty)
    }

    func testPendingRequestsExpireAfterTheirTime() throws {
        try tokens.create(newToken())
        _ = try requests.create(newRequest("mr-1", state: .pendingApproval))
        XCTAssertEqual(try requests.expireOld(now: now.addingTimeInterval(86_399)), 0)
        XCTAssertEqual(try requests.expireOld(now: now.addingTimeInterval(86_400)), 1)
        XCTAssertEqual(try requests.get(id: "mr-1")?.state, .expired)
        XCTAssertFalse(try requests.decide(id: "mr-1", to: .approved, by: "late", now: now))
    }

    func testAFinalStateIsNotOverwritten() throws {
        try tokens.create(newToken())
        _ = try requests.create(newRequest("mr-1"))
        try requests.finish(id: "mr-1", state: .done, result: ["vm": "wl-1"])
        try requests.finish(id: "mr-1", state: .failed, result: ["message": "late"])
        XCTAssertEqual(try requests.get(id: "mr-1")?.state, .done)
        XCTAssertEqual(try requests.get(id: "mr-1")?.result?["vm"] as? String, "wl-1")
    }

    func testTheActivityListsOnlyMcpActorsNewestFirst() throws {
        let audit = AuditStore(database)
        try audit.record(actor: "admin", action: "machine.remove", at: now)
        try audit.record(actor: "mcp:claude", action: "mcp.list_vms", target: "mini", detail: ["status": "ok"], at: now)
        try audit.record(actor: "mcp:ci", action: "mcp.create_vm", at: now)
        let rows = try McpActivityStore(database).recent(limit: 10)
        XCTAssertEqual(rows.map(\.actor), ["mcp:ci", "mcp:claude"])
        XCTAssertEqual(try McpActivityStore(database).recent(limit: 1).count, 1)
    }

    func testPublicKeysWaitingForTheirVmAreFound() throws {
        try tokens.create(newToken())
        _ = try requests.create(NewMcpRequest(id: "mr-1", tokenId: "mt-1", kind: .create, params: ["size": "small", "ssh_public_key": "ssh-ed25519 AAAA"], state: .running, idempotencyKey: nil,
                                              createdAt: now, expiresAt: now.addingTimeInterval(10)))
        XCTAssertEqual(try requests.withPublicKey(token: "mt-1").map(\.id), ["mr-1"])
        try requests.setParams(id: "mr-1", params: ["size": "small"])
        XCTAssertTrue(try requests.withPublicKey(token: "mt-1").isEmpty)
    }
}
