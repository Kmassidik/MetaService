import XCTest
import RootCore
@testable import RootStore

final class McpStoreTests: XCTestCase {
    private var database: Database!
    private var people: McpPeopleStore!
    private var tokens: McpTokenStore!
    private var workloads: McpWorkloadStore!
    private var requests: McpRequestStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        people = McpPeopleStore(database)
        tokens = McpTokenStore(database)
        workloads = McpWorkloadStore(database)
        requests = McpRequestStore(database)
        try people.create(id: "mp-1", name: "Ayu", scopes: [.read, .create], quotas: .defaults, now: now)
    }

    private func newToken(_ id: String = "mt-1", person: String = "mp-1", name: String = "laptop", text: String = "msk_" + String(repeating: "a", count: 43), expires: TimeInterval = 86_400) -> NewMcpToken {
        NewMcpToken(id: id, name: name, prefix: McpToken.displayPrefix(of: text), personId: person, tokenHash: McpToken.hash(text), scopes: [.read, .create], createdBy: "admin",
                    createdAt: now, expiresAt: now.addingTimeInterval(expires))
    }

    private func newRequest(_ id: String, person: String = "mp-1", key: String? = nil) -> NewMcpRequest {
        NewMcpRequest(id: id, personId: person, tokenId: "mt-1", kind: .create, params: ["size": "small"], idempotencyKey: key, createdAt: now)
    }

    private func reserve(_ request: String, person: String = "mp-1", token: String = "mt-1", wish: McpWish = McpWish(vcpu: 1, ramMb: 512, diskGb: 1, gpuMemoryGb: nil)) throws -> Int {
        try workloads.reserve(NewMcpWorkload(personId: person, tokenId: token, machineId: "mini", requestId: request, idempotencyKey: nil, wish: wish, createdAt: now))
    }

    // MARK: tokens

    func testATokenIsFoundByItsHashAndTheTextIsNeverStored() throws {
        let text = "msk_" + String(repeating: "q", count: 43)
        try tokens.create(newToken(text: text))
        let found = try XCTUnwrap(try tokens.find(hash: McpToken.hash(text)))
        XCTAssertEqual(found.name, "laptop")
        XCTAssertEqual(found.personId, "mp-1")
        XCTAssertEqual(found.scopes, [.read, .create])
        XCTAssertNil(try tokens.find(hash: McpToken.hash("msk_" + String(repeating: "z", count: 43))))
        XCTAssertFalse(try database.query("SELECT * FROM api_tokens").map { "\($0)" }.joined().contains(text))
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
        XCTAssertEqual(try tokens.lastUsed(person: "mp-1"), now.addingTimeInterval(61))
    }

    func testTheSameHashCannotBeStoredTwiceAndATokenNeedsAPerson() throws {
        try tokens.create(newToken())
        XCTAssertThrowsError(try tokens.create(newToken("mt-2")))
    }

    func testTheClientANameAndVersionAreKeptOnTheToken() throws {
        try tokens.create(newToken())
        try tokens.setClient(id: "mt-1", name: "claude-code", version: "2.0.1")
        XCTAssertEqual(try tokens.get(id: "mt-1")?.clientName, "claude-code")
        XCTAssertEqual(try tokens.get(id: "mt-1")?.clientVersion, "2.0.1")
        try tokens.setClient(id: "mt-1", name: nil, version: nil)
        XCTAssertNil(try tokens.get(id: "mt-1")?.clientName)
    }

    func testLiveTokensAreCountedPerPerson() throws {
        try tokens.create(newToken())
        try tokens.create(newToken("mt-2", text: "msk_" + String(repeating: "b", count: 43)))
        XCTAssertEqual(try tokens.liveCount(person: "mp-1"), 2)
        try tokens.revoke(id: "mt-2", now: now)
        XCTAssertEqual(try tokens.liveCount(person: "mp-1"), 1)
    }

    // MARK: people

    func testAPersonIsFoundByNameIgnoringCaseAndNamesAreUnique() throws {
        XCTAssertEqual(try people.find(name: "ayu")?.id, "mp-1")
        XCTAssertThrowsError(try people.create(id: "mp-2", name: "Ayu", scopes: [.read], quotas: .defaults, now: now)) { XCTAssertEqual($0 as? McpPeopleError, .nameTaken) }
        XCTAssertEqual(try people.get(id: "mp-1")?.actor, "mcp:Ayu")
    }

    func testChangingScopesAndQuotasKeepsWhatIsNotNamed() throws {
        try people.change(id: "mp-1", scopes: [.read], quotas: nil)
        XCTAssertEqual(try people.get(id: "mp-1")?.scopes, [.read])
        XCTAssertEqual(try people.get(id: "mp-1")?.quotas, .defaults)
        let tight = McpQuotas(maxVms: 1, maxVcpu: 1, maxRamMb: 512, maxDiskGb: 1, createsPerDay: 1, gpuMemoryGb: 1)
        try people.change(id: "mp-1", scopes: nil, quotas: tight)
        XCTAssertEqual(try people.get(id: "mp-1")?.quotas, tight)
        XCTAssertEqual(try people.get(id: "mp-1")?.scopes, [.read])
        XCTAssertThrowsError(try people.change(id: "mp-nope", scopes: [.read], quotas: nil))
    }

    func testDisablingAndEnablingAPerson() throws {
        XCTAssertTrue(try people.setDisabled(id: "mp-1", true, now: now))
        XCTAssertFalse(try people.setDisabled(id: "mp-1", true, now: now))
        XCTAssertEqual(try people.get(id: "mp-1")?.isDisabled, true)
        XCTAssertTrue(try people.setDisabled(id: "mp-1", false, now: now))
        XCTAssertEqual(try people.get(id: "mp-1")?.isDisabled, false)
    }

    // MARK: ownership and quotas, by person

    func testTwoTokensOfOnePersonShareOneCountAndAnotherPersonSeesNothing() throws {
        try people.create(id: "mp-2", name: "Budi", scopes: [.read], quotas: .defaults, now: now)
        try tokens.create(newToken())
        try tokens.create(newToken("mt-2", text: "msk_" + String(repeating: "b", count: 43)))
        let big = McpWish(vcpu: 2, ramMb: 4096, diskGb: 40, gpuMemoryGb: nil)
        let first = try reserve("mr-1", token: "mt-1", wish: big)
        _ = try reserve("mr-2", token: "mt-2", wish: big)
        XCTAssertEqual(try workloads.usage(person: "mp-1", now: now), McpUsage(aliveVms: 2, vcpu: 4, ramMb: 8192, diskGb: 80, createsLastDay: 2))
        XCTAssertEqual(try workloads.usage(person: "mp-2", now: now), McpUsage(aliveVms: 0, vcpu: 0, ramMb: 0, diskGb: 0, createsLastDay: 0))
        try workloads.setWorkload(row: first, workload: "vm-1")
        XCTAssertNotNil(try workloads.find(person: "mp-1", machine: "mini", workload: "vm-1"))
        XCTAssertNil(try workloads.find(person: "mp-2", machine: "mini", workload: "vm-1"))
        try workloads.markDeleted(row: first, now: now)
        XCTAssertEqual(try workloads.usage(person: "mp-1", now: now), McpUsage(aliveVms: 1, vcpu: 2, ramMb: 4096, diskGb: 40, createsLastDay: 2))
        XCTAssertEqual(try workloads.usage(person: "mp-1", now: now.addingTimeInterval(86_401)).createsLastDay, 0)
    }

    func testARemovedReservationFreesTheSlotAndTheCount() throws {
        try tokens.create(newToken())
        try workloads.remove(row: try reserve("mr-1"))
        XCTAssertEqual(try workloads.usage(person: "mp-1", now: now), McpUsage(aliveVms: 0, vcpu: 0, ramMb: 0, diskGb: 0, createsLastDay: 0))
    }

    // MARK: requests

    func testARepeatedKeyOfThePersonReturnsTheFirstRequestEvenFromAnotherToken() throws {
        try tokens.create(newToken())
        let first = try requests.create(newRequest("mr-1", key: "k1"))
        let second = try requests.create(newRequest("mr-2", key: "k1"))
        XCTAssertTrue(first.created)
        XCTAssertFalse(second.created)
        XCTAssertEqual(second.request.id, "mr-1")
        XCTAssertNil(try requests.get(id: "mr-2"))
    }

    func testTheSameKeyOfAnotherPersonIsAnotherRequest() throws {
        try tokens.create(newToken())
        try people.create(id: "mp-2", name: "Budi", scopes: [.read], quotas: .defaults, now: now)
        XCTAssertTrue(try requests.create(newRequest("mr-1", key: "k1")).created)
        XCTAssertTrue(try requests.create(newRequest("mr-2", person: "mp-2", key: "k1")).created)
    }

    func testARequestStartsRunningAndEndsOnce() throws {
        try tokens.create(newToken())
        _ = try requests.create(newRequest("mr-1"))
        XCTAssertEqual(try requests.get(id: "mr-1")?.state, .running)
        XCTAssertEqual(try requests.unfinished(person: "mp-1").map(\.id), ["mr-1"])
        try requests.finish(id: "mr-1", state: .done, result: ["vm": "vm-1"])
        try requests.finish(id: "mr-1", state: .failed, result: ["message": "late"])
        XCTAssertEqual(try requests.get(id: "mr-1")?.state, .done)
        XCTAssertEqual(try requests.get(id: "mr-1")?.result?["vm"] as? String, "vm-1")
        XCTAssertTrue(try requests.unfinished(person: "mp-1").isEmpty)
    }

    func testPublicKeysWaitingForTheirVmAreFound() throws {
        try tokens.create(newToken())
        _ = try requests.create(NewMcpRequest(id: "mr-1", personId: "mp-1", tokenId: "mt-1", kind: .create, params: ["size": "small", "ssh_public_key": "ssh-ed25519 AAAA"], idempotencyKey: nil, createdAt: now))
        XCTAssertEqual(try requests.withPublicKey(person: "mp-1").map(\.id), ["mr-1"])
        try requests.setParams(id: "mr-1", params: ["size": "small"])
        XCTAssertTrue(try requests.withPublicKey(person: "mp-1").isEmpty)
    }

    func testTheActivityListsOnlyMcpActorsNewestFirst() throws {
        let audit = AuditStore(database)
        try audit.record(actor: "admin", action: "machine.remove", at: now)
        try audit.record(actor: "mcp:Ayu", action: "mcp.list_vms", target: "mini", detail: ["status": "ok"], at: now)
        try audit.record(actor: "mcp:Budi", action: "mcp.create_vm", at: now)
        let rows = try McpActivityStore(database).recent(limit: 10)
        XCTAssertEqual(rows.map(\.actor), ["mcp:Budi", "mcp:Ayu"])
        XCTAssertEqual(try McpActivityStore(database).recent(limit: 1).count, 1)
    }
}
