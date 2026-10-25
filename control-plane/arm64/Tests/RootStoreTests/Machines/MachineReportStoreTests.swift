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

    private static let card: [String: Any] = ["vendor": "nvidia", "model": "NVIDIA GeForce RTX 5090", "memory_mb": 32768, "architecture": "Blackwell",
                                              "compute_capability": "12.0", "driver_version": "580.178.04", "max_clock_mhz": 3090, "uses_system_memory": false]

    private func heartbeat(hardware: [String: Any]?, gpu: [[String: Any]] = []) throws -> HeartbeatRequest {
        var facts: [String: Any] = ["os": "linux", "arch": "x86_64", "cpu_cores": 64, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 50000, "free_disk_gb": 800,
                                    "gpu": gpu, "capabilities": ["vm": true, "container": false, "gpu_in_vm": false, "gpu_in_container": false]]
        facts["hardware"] = hardware
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: ["facts": facts, "workloads": []]))
    }

    private func listedJson() throws -> [String: Any] {
        let snake = JSONEncoder()
        snake.keyEncodingStrategy = .convertToSnakeCase
        return try JSONSerialization.jsonObject(with: snake.encode(try XCTUnwrap(try machines.list(now: now).first))) as! [String: Any]
    }

    func testTheHardwareIsKeptCleanedReplacedAndClearedWhenNotSaid() throws {
        XCTAssertNil(try machines.get(id: "mini", now: now).hardware)
        let server: [String: Any] = ["system": "Dell  PowerEdge\u{0} R7525", "core_types": [["name": "AMD EPYC 7763 64-Core Processor", "cores": 64, "max_mhz": 3529]],
                                     "disks": [["model": "Dell Ent NVMe P5600 MU U.2 3.2TB", "size_gb": 3200, "kind": "nvme"]]]
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(hardware: server), ip: nil, now: now)
        let kept = HardwareReport(system: "Dell PowerEdge R7525", coreTypes: [.init(name: "AMD EPYC 7763 64-Core Processor", cores: 64, maxMhz: 3529)],
                                  disks: [.init(model: "Dell Ent NVMe P5600 MU U.2 3.2TB", sizeGb: 3200, kind: "nvme")])
        XCTAssertEqual(try machines.get(id: "mini", now: now).hardware, kept)
        XCTAssertEqual(try machines.list(now: now).first?.hardware, kept)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(hardware: ["system": "NVIDIA DGX Spark"]), ip: nil, now: now)
        XCTAssertEqual(try machines.get(id: "mini", now: now).hardware, HardwareReport(system: "NVIDIA DGX Spark"), "the next heartbeat replaces the whole report")
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(hardware: nil), ip: nil, now: now)
        XCTAssertNil(try machines.get(id: "mini", now: now).hardware, "a helper that does not say it must not keep the last answer")
    }

    func testTheHardwareIsInTheJsonOfEveryMachineInSnakeCaseAsNullWhenNotSaidAndWithoutTheLeftOutParts() throws {
        XCTAssertTrue(try listedJson()["hardware"] is NSNull)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(hardware: ["core_types": [["name": "Cortex-X925", "cores": 10, "max_mhz": 4004], ["name": "Cortex-A725", "cores": 10]],
                                                                                          "disks": [["model": "ESL04TBTLCZ-27J2-TYN", "size_gb": 4096, "kind": "nvme"]]]), ip: nil, now: now)
        let hardware = try XCTUnwrap(try listedJson()["hardware"] as? [String: Any])
        XCTAssertEqual(Set(hardware.keys), ["core_types", "disks"], "a part the helper left out is left out, not null")
        let cores = try XCTUnwrap(hardware["core_types"] as? [[String: Any]])
        XCTAssertEqual(cores[0]["max_mhz"] as? Int, 4004)
        XCTAssertEqual(Set(cores[1].keys), ["name", "cores"])
        let disk = try XCTUnwrap((hardware["disks"] as? [[String: Any]])?.first)
        XCTAssertEqual(disk["size_gb"] as? Int, 4096)
        XCTAssertEqual(disk["kind"] as? String, "nvme")
    }

    func testTheGpuDetailsAreKeptAndInTheJsonInSnakeCase() throws {
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(hardware: nil, gpu: [Self.card]), ip: nil, now: now)
        XCTAssertEqual(try machines.get(id: "mini", now: now).gpu, [GpuInfo(vendor: "nvidia", model: "NVIDIA GeForce RTX 5090", memoryMb: 32768, architecture: "Blackwell",
                                                                             computeCapability: "12.0", driverVersion: "580.178.04", maxClockMhz: 3090, usesSystemMemory: false)])
        let card = try XCTUnwrap((try listedJson()["gpu"] as? [[String: Any]])?.first)
        XCTAssertEqual(card["compute_capability"] as? String, "12.0")
        XCTAssertEqual(card["driver_version"] as? String, "580.178.04")
        XCTAssertEqual(card["max_clock_mhz"] as? Int, 3090)
        XCTAssertEqual(card["uses_system_memory"] as? Bool, false)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(hardware: nil, gpu: [["vendor": "nvidia", "model": "NVIDIA GB10", "uses_system_memory": true]]), ip: nil, now: now)
        let spark = try XCTUnwrap((try listedJson()["gpu"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(spark.keys), ["vendor", "model", "uses_system_memory"], "details the helper does not say are left out, like memory_mb")
    }

    func testAGpuListSavedBeforeTheDetailsStillReads() throws {
        try database.execute("UPDATE machines SET gpu_json = ? WHERE id = ?", [.text(#"[{"vendor":"nvidia","model":"NVIDIA GB10","memoryMb":131072}]"#), .text("mini")])
        XCTAssertEqual(try machines.get(id: "mini", now: now).gpu, [GpuInfo(vendor: "nvidia", model: "NVIDIA GB10", memoryMb: 131072)])
    }

    private func heartbeat(sandbox: [String: Any]?) throws -> HeartbeatRequest {
        var caps: [String: Any] = ["vm": true, "container": false, "gpu_in_vm": false, "gpu_in_container": false]
        if sandbox != nil { caps["sandbox"] = true }
        var facts: [String: Any] = ["os": "linux", "arch": "x86_64", "cpu_cores": 64, "ram_total_mb": 65536, "disk_total_gb": 1000,
                                    "free_ram_mb": 50000, "free_disk_gb": 800, "gpu": [], "capabilities": caps]
        facts["sandbox"] = sandbox
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: ["facts": facts, "workloads": []]))
    }

    private func sandboxFacts(running: Int = 2) -> [String: Any] {
        ["engine": ["name": "firecracker", "version": "1.7.0"], "max_running": 20, "running": running, "paused": 1,
         "max_vcpu": 8, "max_ram_mb": 16384, "max_disk_mb": 102400, "booked": ["vcpu": 4, "ram_mb": 4096, "disk_mb": 20480],
         "templates": [["id": "base", "build": "b1", "ready": true]], "changes": 7]
    }

    func testTheSandboxFactsAreKeptInSnakeCaseAndGoWhenNoLongerSaid() throws {
        XCTAssertNil(try machines.get(id: "mini", now: now).sandbox)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(sandbox: sandboxFacts()), ip: nil, now: now)
        let seen = try machines.get(id: "mini", now: now)
        XCTAssertEqual(seen.sandbox?.running, 2)
        XCTAssertEqual(seen.sandbox?.engine, SandboxFacts.Engine(name: "firecracker", version: "1.7.0"))
        XCTAssertEqual(seen.capabilities?.sandbox, true)
        let snake = JSONEncoder()
        snake.keyEncodingStrategy = .convertToSnakeCase
        let json = try JSONSerialization.jsonObject(with: snake.encode(try XCTUnwrap(try machines.list(now: now).first))) as! [String: Any]
        let sandbox = json["sandbox"] as! [String: Any]
        XCTAssertEqual(sandbox["max_running"] as? Int, 20)
        XCTAssertEqual((sandbox["booked"] as! [String: Any])["disk_mb"] as? Int, 20480)
        XCTAssertEqual((sandbox["templates"] as! [[String: Any]])[0]["id"] as? String, "base")
        XCTAssertEqual((json["capabilities"] as! [String: Any])["sandbox"] as? Bool, true)
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(sandbox: nil), ip: nil, now: now)
        XCTAssertNil(try machines.get(id: "mini", now: now).sandbox, "a helper that stops saying it must not keep the last answer")
        XCTAssertEqual(try machines.get(id: "mini", now: now).capabilities?.sandbox, false)
    }

    func testTheSandboxIsAlsoInTheListWithAnUnknownVersionAsNull() throws {
        var facts = sandboxFacts()
        facts["engine"] = ["name": "firecracker"]
        try machines.recordHeartbeat(machineId: "mini", request: try heartbeat(sandbox: facts), ip: nil, now: now)
        let listed = try XCTUnwrap(try machines.list(now: now).first?.sandbox)
        XCTAssertNil(listed.engine.version)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(listed)) as! [String: Any]
        XCTAssertTrue((json["engine"] as! [String: Any])["version"] is NSNull)
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
