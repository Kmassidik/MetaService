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

final class BundleStoreTests: XCTestCase {
    private var database: Database!
    private var directory: String!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        directory = NSTemporaryDirectory() + "ms-bundles-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    private func drop(_ version: String, _ text: String = "content", platform: String = "noarch") {
        FileManager.default.createFile(atPath: "\(directory!)/metaservice-chat-\(version)-\(platform).tar.gz", contents: Data(text.utf8))
    }

    func testTheFolderBecomesTheRegistryWithRealChecksums() throws {
        drop("0.1.0", "abc")
        drop("0.2.0")
        FileManager.default.createFile(atPath: directory + "/notes.txt", contents: Data("x".utf8))
        FileManager.default.createFile(atPath: directory + "/metaservice-chat-9.9-noarch.tar.gz", contents: Data("x".utf8))
        let overview = try BundleStore(database, directory: directory).overview(now: now)
        XCTAssertEqual(overview.bundles.map(\.version), ["0.2.0", "0.1.0"])
        XCTAssertEqual(overview.bundles[1].sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertNil(overview.pinned)
    }

    func testPinningRollbackAndTheMissingCases() throws {
        let bundles = BundleStore(database, directory: directory)
        drop("0.1.0"); drop("0.2.0")
        XCTAssertThrowsError(try bundles.pin(version: "9.9.9", actor: "k", now: now)) { XCTAssertEqual($0 as? BundleError, .unknownVersion) }
        XCTAssertThrowsError(try bundles.rollback(actor: "k", now: now)) { XCTAssertEqual($0 as? BundleError, .nothingToRollBackTo) }
        try bundles.pin(version: "0.1.0", actor: "k", now: now)
        XCTAssertThrowsError(try bundles.rollback(actor: "k", now: now), "one pin only: nothing before it")
        try bundles.pin(version: "0.2.0", actor: "k", now: now)
        XCTAssertEqual(try bundles.pinned(), "0.2.0")
        XCTAssertEqual(try bundles.previous(), "0.1.0")
        XCTAssertEqual(try bundles.rollback(actor: "k", now: now), "0.1.0")
        XCTAssertEqual(try bundles.pinned(), "0.1.0")
        XCTAssertEqual(try bundles.previous(), "0.2.0", "going forward again is the same one step")
        XCTAssertEqual(try bundles.overview(now: now).bundles.filter(\.pinned).map(\.version), ["0.1.0"])
    }

    func testAChangedFileIsHashedAgainAndAGoneFileDisappears() throws {
        let bundles = BundleStore(database, directory: directory)
        drop("0.1.0", "one")
        let first = try bundles.overview(now: now).bundles[0].sha256
        drop("0.1.0", "two!")
        XCTAssertNotEqual(try bundles.overview(now: now).bundles[0].sha256, first)
        try FileManager.default.removeItem(atPath: "\(directory!)/metaservice-chat-0.1.0-noarch.tar.gz")
        XCTAssertTrue(try bundles.overview(now: now).bundles.isEmpty)
        XCTAssertNil(try bundles.find(version: "0.1.0", platform: "noarch"))
    }

    func testChatKeysAreStoredPerTarget() throws {
        let access = ChatAccessStore(database)
        try access.set(target: "mini", sealedKey: "s1", port: 9200, now: now)
        try access.set(target: "mini/w-1", sealedKey: "s2", port: 9200, now: now)
        XCTAssertEqual(try access.get(target: "mini")?.sealedKey, "s1")
        try access.set(target: "mini", sealedKey: "s3", port: 9201, now: now)
        XCTAssertEqual(try access.get(target: "mini")?.port, 9201)
        try access.remove(target: "mini")
        XCTAssertNil(try access.get(target: "mini"))
        XCTAssertNil(try access.get(target: "mini/w-1"), "removing a machine removes its workloads' keys too")
    }
}
