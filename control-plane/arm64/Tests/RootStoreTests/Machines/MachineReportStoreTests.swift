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

    private let build = String(repeating: "ab", count: 32)

    private func heartbeat(build: String?) throws -> HeartbeatRequest {
        var facts: [String: Any] = ["os": "macos", "arch": "arm64", "cpu_cores": 10, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 50000, "free_disk_gb": 800,
                                    "gpu": [], "capabilities": ["vm": true, "container": false, "gpu_in_vm": false, "gpu_in_container": false]]
        facts["agent_build"] = build
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: ["facts": facts, "workloads": []]))
    }

    func testTheHelperBuildIsKeptAsReportedAndIsInTheListToo() throws {
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(build: build), ip: nil, now: now)
        XCTAssertEqual(try machines.get(id: "mini", now: now).agentBuild, build)
        XCTAssertEqual(try machines.list(now: now).first?.agentBuild, build)
    }

    func testTheBuildIsReplacedByTheNextHeartbeatAndClearedWhenItIsNotSaid() throws {
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(build: build), ip: nil, now: now)
        let newer = String(repeating: "cd", count: 32)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(build: newer), ip: nil, now: now)
        XCTAssertEqual(try machines.get(id: "mini", now: now).agentBuild, newer)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(build: nil), ip: nil, now: now)
        XCTAssertNil(try machines.get(id: "mini", now: now).agentBuild, "an older helper that does not say it must not keep the last answer")
    }

    private func heartbeat(cpuModel: String?) throws -> HeartbeatRequest {
        var facts: [String: Any] = ["os": "linux", "arch": "x86_64", "cpu_cores": 64, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 50000, "free_disk_gb": 800,
                                    "gpu": [], "capabilities": ["vm": true, "container": false, "gpu_in_vm": false, "gpu_in_container": false]]
        facts["cpu_model"] = cpuModel
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: ["facts": facts, "workloads": []]))
    }

    func testTheCpuNameIsKeptCleanedReplacedAndClearedWhenNotSaid() throws {
        XCTAssertNil(try machines.get(id: "mini", now: now).cpuModel)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(cpuModel: "AMD  EPYC\u{0} 7763"), ip: nil, now: now)
        XCTAssertEqual(try machines.get(id: "mini", now: now).cpuModel, "AMD EPYC 7763")
        XCTAssertEqual(try machines.list(now: now).first?.cpuModel, "AMD EPYC 7763")
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(cpuModel: "Apple M4"), ip: nil, now: now)
        XCTAssertEqual(try machines.get(id: "mini", now: now).cpuModel, "Apple M4")
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(cpuModel: nil), ip: nil, now: now)
        XCTAssertNil(try machines.get(id: "mini", now: now).cpuModel, "an older helper that does not say it must not keep the last answer")
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

    private func beat(state: String, extra: [String: Any] = [:]) throws -> HeartbeatRequest {
        var workload: [String: Any] = ["id": "w-1", "name": "test", "kind": "vm", "state": state, "cpu": 2, "ram_mb": 2048, "disk_gb": 10, "gpu_mode": "none", "address": NSNull()]
        workload.merge(extra) { $1 }
        let facts: [String: Any] = ["os": "macos", "arch": "arm64", "cpu_cores": 10, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 50000, "free_disk_gb": 800,
                                    "gpu": [], "capabilities": ["vm": true, "container": false, "gpu_in_vm": false, "gpu_in_container": false]]
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: ["facts": facts, "workloads": [workload]]))
    }

    func testAStoppedVmKeepsItsReasonAndItGoesWhenTheVmRunsAgainOrIsGone() throws {
        let reason: [String: Any] = ["exit_code": 255, "log_tail": "Failed to mount API filesystems."]
        try machines.recordHeartbeat(machineId: "mini", request: try beat(state: "stopped", extra: ["stopped_reason": reason, "init_mode": "plain"]), ip: nil, now: now)
        var seen = try XCTUnwrap(try machines.get(id: "mini", now: now).workloads.first)
        XCTAssertEqual(seen.stoppedReason, StoppedReasonReport(exitCode: 255, logTail: "Failed to mount API filesystems."))
        XCTAssertEqual(seen.initMode, "plain")
        try machines.recordHeartbeat(machineId: "mini", request: try beat(state: "running", extra: ["stopped_reason": reason]), ip: nil, now: now)
        seen = try XCTUnwrap(try machines.get(id: "mini", now: now).workloads.first)
        XCTAssertNil(seen.stoppedReason, "a VM that runs again has no reason")
        XCTAssertNil(seen.initMode)
        try machines.recordHeartbeat(machineId: "mini", request: try beat(state: "stopped", extra: ["stopped_reason": reason]), ip: nil, now: now)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(), ip: nil, now: now)
        XCTAssertTrue(try machines.get(id: "mini", now: now).workloads.isEmpty)
        try machines.recordHeartbeat(machineId: "mini", request: try beat(state: "stopped"), ip: nil, now: now)
        XCTAssertNil(try machines.get(id: "mini", now: now).workloads.first?.stoppedReason, "a deleted VM's reason is not remembered")
    }

    func testTheReasonAndTheModeAreInTheJsonOfEveryWorkloadAsNullWhenEmpty() throws {
        try machines.recordHeartbeat(machineId: "mini", request: try beat(state: "stopped"), ip: nil, now: now)
        let snake = JSONEncoder()
        snake.keyEncodingStrategy = .convertToSnakeCase
        let listed = try XCTUnwrap(try machines.list(now: now).first?.workloads.first)
        let json = try JSONSerialization.jsonObject(with: snake.encode(listed)) as! [String: Any]
        XCTAssertTrue(json["stopped_reason"] is NSNull)
        XCTAssertTrue(json["init_mode"] is NSNull)
        try machines.recordHeartbeat(machineId: "mini", request: try beat(state: "stopped", extra: ["stopped_reason": ["exit_code": NSNull(), "log_tail": "<b>x</b>"]]), ip: nil, now: now)
        let again = try JSONSerialization.jsonObject(with: snake.encode(try XCTUnwrap(try machines.list(now: now).first?.workloads.first))) as! [String: Any]
        let reason = again["stopped_reason"] as! [String: Any]
        XCTAssertTrue(reason["exit_code"] is NSNull)
        XCTAssertEqual(reason["log_tail"] as? String, "<b>x</b>")
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
