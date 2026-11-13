import XCTest
import RootCore
@testable import RootStore

/// Answers 7 ms for the machine "a" and nothing (a failed probe) for any other machine.
private struct FakeConnector: LatencyConnector {
    func answerMillis(for target: LatencyTarget, timeout: TimeInterval) async -> Int? {
        target.machineId == "a" ? 7 : nil
    }
}

final class LatencyStoreTests: XCTestCase {
    private var database: Database!
    private var store: LatencyStore!

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = LatencyStore(database)
    }

    private func sample(_ machine: String, _ at: Int, _ millis: Int?) -> LatencySample {
        LatencySample(machineId: machine, at: at, millis: millis)
    }

    func testARecordedSampleReadsBackIncludingAFailure() throws {
        try store.record([sample("a", 100, 7), sample("a", 110, nil)])
        XCTAssertEqual(try store.samples(machineId: "a", since: 0), [sample("a", 100, 7), sample("a", 110, nil)])
    }

    func testReadingStartsAtSinceAndStaysWithOneMachine() throws {
        try store.record([sample("a", 100, 1), sample("a", 200, 2), sample("b", 200, 3)])
        XCTAssertEqual(try store.samples(machineId: "a", since: 150), [sample("a", 200, 2)])
    }

    func testDeleteOlderThanRemovesOnlyTheOldRows() throws {
        try store.record([sample("a", 100, 1), sample("a", 200, 2), sample("b", 50, 3)])
        try store.deleteOlderThan(150)
        XCTAssertEqual(try store.samples(machineId: "a", since: 0), [sample("a", 200, 2)])
        XCTAssertEqual(try store.samples(machineId: "b", since: 0), [])
    }

    func testTheSameMachineAndTimeTwiceKeepsOneRow() throws {
        try store.record([sample("a", 100, 1)])
        try store.record([sample("a", 100, 9)])
        XCTAssertEqual(try store.samples(machineId: "a", since: 0), [sample("a", 100, 9)])
    }

    func testTheSchemaIsAtVersion32() throws {
        XCTAssertEqual(Migrations.latest, 34)
        XCTAssertEqual(try database.query("SELECT MAX(version) AS v FROM schema_version").first?.int("v"), 34)
    }

    /// One pass of the prober: every machine gets one sample at the same time, and the store keeps them.
    func testOnePassStoresOneSampleForEachMachine() async throws {
        let targets = [LatencyTarget(machineId: "a", host: "a", port: 9101), LatencyTarget(machineId: "b", host: "b", port: 9101)]
        let samples = await LatencyRound.run(targets, at: 1_800_000_000, connector: FakeConnector(), timeout: 3)
        try store.record(samples)
        XCTAssertEqual(try store.samples(machineId: "a", since: 0), [sample("a", 1_800_000_000, 7)])
        XCTAssertEqual(try store.samples(machineId: "b", since: 0), [sample("b", 1_800_000_000, nil)])
    }
}
