import XCTest
import RootCore
@testable import RootStore

final class CommandStoreTests: XCTestCase {
    private var database: Database!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        try MachineStore(database).enroll(name: "mini", tokenHash: "h", commandTokenSealed: "sealed-secret", ip: "10.0.0.5", now: now)
    }

    func testACommandMovesFromQueuedToFinished() throws {
        let commands = CommandStore(database)
        try commands.create(id: "rc-1", machine: "mini", workloadId: nil, type: "create", params: ["ram_mb": "2048", "disk_gb": "20"], actor: "k@example.com", now: now)
        XCTAssertEqual(try commands.get("rc-1")?.state, "queued")
        try commands.update(id: "rc-1", state: "running", result: nil, now: now)
        XCTAssertNil(try commands.get("rc-1")?.finishedAt)
        try commands.update(id: "rc-1", state: "succeeded", result: ["workload_id": "w-1"], now: now.addingTimeInterval(5))
        let done = try XCTUnwrap(try commands.get("rc-1"))
        XCTAssertEqual(done.result, ["workload_id": "w-1"])
        XCTAssertNotNil(done.finishedAt)
        XCTAssertNil(try commands.get("rc-2"))
    }

    func testPromisedRoomCountsOnlyUnfinishedCreates() throws {
        let commands = CommandStore(database)
        try commands.create(id: "a", machine: "mini", workloadId: nil, type: "create", params: ["ram_mb": "1000", "disk_gb": "10"], actor: "k", now: now)
        try commands.create(id: "b", machine: "mini", workloadId: nil, type: "create", params: ["ram_mb": "500", "disk_gb": "5"], actor: "k", now: now)
        try commands.create(id: "c", machine: "mini", workloadId: "w-1", type: "stop", params: [:], actor: "k", now: now)
        XCTAssertEqual(try commands.promised(machine: "mini").ramMb, 1500)
        XCTAssertEqual(try commands.promised(machine: "mini").diskGb, 15)
        try commands.update(id: "a", state: "succeeded", result: nil, now: now)
        XCTAssertEqual(try commands.promised(machine: "mini").ramMb, 500)
        XCTAssertEqual(try commands.promised(machine: "other").ramMb, 0)
        XCTAssertEqual(try commands.unfinished().map(\.id).sorted(), ["b", "c"])
    }

    func testRecentIsNewestFirstAndBounded() throws {
        let commands = CommandStore(database)
        for index in 1...5 { try commands.create(id: "c\(index)", machine: "mini", workloadId: nil, type: "stop", params: [:], actor: "k", now: now.addingTimeInterval(Double(index))) }
        XCTAssertEqual(try commands.recent(limit: 2).map(\.id), ["c5", "c4"])
        XCTAssertEqual(try commands.recent(limit: 100_000).count, 5)
    }

    func testTheEndpointComesFromTheMachineRowAndRemovingTheMachineRemovesItsCommands() throws {
        let machines = MachineStore(database)
        XCTAssertEqual(try machines.endpoint(id: "mini"), AgentEndpoint(ip: "10.0.0.5", port: 9101, sealedCommandToken: "sealed-secret"))
        XCTAssertNil(try machines.endpoint(id: "nobody"))
        try CommandStore(database).create(id: "x", machine: "mini", workloadId: nil, type: "stop", params: [:], actor: "k", now: now)
        try machines.remove(id: "mini")
        XCTAssertNil(try CommandStore(database).get("x"))
    }

    func testHostileTextInParamsAndResultsIsStoredAsText() throws {
        let commands = CommandStore(database)
        let hostile = "x'; DROP TABLE commands;--"
        try commands.create(id: "h", machine: "mini", workloadId: nil, type: "create", params: ["name": hostile], actor: hostile, now: now)
        try commands.update(id: "h", state: "failed", result: ["error": hostile], now: now)
        XCTAssertEqual(try commands.get("h")?.result?["error"], hostile)
        XCTAssertEqual(try commands.get("h")?.actor, hostile)
    }
}
