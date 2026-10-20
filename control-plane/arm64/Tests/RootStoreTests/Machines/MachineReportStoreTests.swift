import XCTest
import RootCore
@testable import RootStore

final class MachineReportStoreTests: XCTestCase {
    private var database: Database!
    private var machines: MachineStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        machines = MachineStore(database)
        try machines.enroll(name: "mini", tokenHash: "h", commandTokenSealed: "sealed", ip: nil, now: now)
    }

    private func heartbeat(agentVersion: String? = nil, engine: [String: Any]? = nil, bundleVersion: String? = nil) throws -> HeartbeatRequest {
        var facts: [String: Any] = ["os": "macos", "arch": "arm64", "cpu_cores": 10, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 50000, "free_disk_gb": 800,
                                    "gpu": [], "capabilities": ["vm": true, "container": false, "gpu_in_vm": false, "gpu_in_container": false]]
        facts["agent_version"] = agentVersion
        facts["engine"] = engine
        var body: [String: Any] = ["facts": facts, "workloads": []]
        body["bundle_version"] = bundleVersion
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: body))
    }

    func testTheHelperVersionAndTheEngineAreKeptAsReported() throws {
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(agentVersion: "0.2.0", engine: ["name": "apple-container", "version": "1.5.0", "ready": true]), ip: nil, now: now)
        let seen = try machines.get(id: "mini", now: now)
        XCTAssertEqual(seen.agentVersion, "0.2.0")
        XCTAssertEqual(seen.engine, EngineReport(name: "apple-container", version: "1.5.0", ready: true))
    }

    func testBeforeAnyHeartbeatNothingIsInventedAboutTheHelperOrTheEngine() throws {
        let seen = try machines.get(id: "mini", now: now)
        XCTAssertNil(seen.agentVersion)
        XCTAssertNil(seen.engine)
    }

    func testAHeartbeatThatNoLongerSaysItClearsTheOldAnswer() throws {
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(agentVersion: "0.2.0", engine: ["name": "incus", "ready": true]), ip: nil, now: now)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(), ip: nil, now: now)
        let seen = try machines.get(id: "mini", now: now)
        XCTAssertNil(seen.agentVersion)
        XCTAssertNil(seen.engine)
    }

    func testTheEngineIsAlsoInTheListWithAnUnknownVersionAsNull() throws {
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(engine: ["name": "incus", "ready": false]), ip: nil, now: now)
        let listed = try XCTUnwrap(try machines.list(now: now).first)
        XCTAssertEqual(listed.engine, EngineReport(name: "incus", version: nil, ready: false))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(listed)) as! [String: Any]
        XCTAssertTrue((json["engine"] as! [String: Any])["version"] is NSNull)
    }

    func testRenamingChangesTheNameButNotTheId() throws {
        try machines.rename(id: "mini", to: "studio")
        let seen = try machines.get(id: "mini", now: now)
        XCTAssertEqual([seen.id, seen.name], ["mini", "studio"])
    }

    func testRenamingToAnotherMachinesNameOrOfAMissingMachineIsRefused() throws {
        try machines.enroll(name: "dgx", tokenHash: "h2", commandTokenSealed: "sealed", ip: nil, now: now)
        XCTAssertThrowsError(try machines.rename(id: "mini", to: "dgx")) { XCTAssertEqual($0 as? MachineError, .exists) }
        XCTAssertThrowsError(try machines.rename(id: "nobody", to: "free-name")) { XCTAssertEqual($0 as? MachineError, .notFound) }
        XCTAssertEqual(try machines.get(id: "mini", now: now).name, "mini")
    }

    func testHostileNamesAreKeptAsTextAndTheTablesSurvive() throws {
        let hostile = "x'; DROP TABLE machines;--"
        try machines.rename(id: "mini", to: hostile)
        XCTAssertEqual(try machines.get(id: "mini", now: now).name, hostile)
    }
}
