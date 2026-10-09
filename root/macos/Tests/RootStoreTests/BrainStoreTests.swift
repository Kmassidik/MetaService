import XCTest
@testable import RootStore

final class BrainStoreTests: XCTestCase {
    private var store: BrainStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = BrainStore(database)
    }

    func testACapabilityWorksUntilItExpires() throws {
        try store.issue(tokenHash: "h1", machine: "mini", workload: nil, expiresAt: now.addingTimeInterval(600), now: now)
        XCTAssertEqual(try store.lookup(tokenHash: "h1", now: now.addingTimeInterval(599)), BrainGrant(machine: "mini", workload: nil))
        XCTAssertNil(try store.lookup(tokenHash: "h1", now: now.addingTimeInterval(600)))
        XCTAssertNil(try store.lookup(tokenHash: "h2", now: now))
    }

    func testAWorkloadCapabilityRemembersItsWorkload() throws {
        try store.issue(tokenHash: "h1", machine: "mini", workload: "w-1", expiresAt: now.addingTimeInterval(60), now: now)
        XCTAssertEqual(try store.lookup(tokenHash: "h1", now: now), BrainGrant(machine: "mini", workload: "w-1"))
    }

    func testIssuingForgetsCapabilitiesThatAlreadyExpired() throws {
        try store.issue(tokenHash: "old", machine: "mini", workload: nil, expiresAt: now.addingTimeInterval(60), now: now)
        let later = now.addingTimeInterval(3600)
        try store.issue(tokenHash: "new", machine: "mini", workload: nil, expiresAt: later.addingTimeInterval(60), now: later)
        XCTAssertNil(try store.lookup(tokenHash: "old", now: now))
        XCTAssertNotNil(try store.lookup(tokenHash: "new", now: later))
    }

    func testUsageAddsUpPerMachineAndPerWorkload() throws {
        try store.record(machine: "mini", workload: nil, promptTokens: 10, completionTokens: 4, now: now)
        try store.record(machine: "mini", workload: nil, promptTokens: 5, completionTokens: 1, now: now)
        try store.record(machine: "mini", workload: "w-1", promptTokens: 7, completionTokens: 2, now: now)
        try store.record(machine: "dgx", workload: nil, promptTokens: 1, completionTokens: 1, now: now)
        XCTAssertEqual(try store.usage(), [
            BrainUsage(machine: "dgx", workload: nil, requests: 1, promptTokens: 1, completionTokens: 1),
            BrainUsage(machine: "mini", workload: nil, requests: 2, promptTokens: 15, completionTokens: 5),
            BrainUsage(machine: "mini", workload: "w-1", requests: 1, promptTokens: 7, completionTokens: 2),
        ])
    }

    func testTheSchemaHoldsNoPlainCapabilityOrKeyColumn() throws {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        let columns = try database.query("SELECT name FROM pragma_table_info('brain_capabilities')").map { $0.string("name") }
        XCTAssertEqual(columns, ["token_hash", "machine", "workload", "expires_at"])
    }
}
