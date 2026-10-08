import XCTest
import MSCore
@testable import AgentCore

final class AgentCoreTests: XCTestCase {
    private func create(_ change: ((inout [String: Any]) -> Void)? = nil) throws -> CreateWorkloadRequest {
        var body: [String: Any] = ["command_id": "c-1", "name": "demo", "kind": "container", "cpu": 2, "ram_mb": 2048, "disk_gb": 10]
        change?(&body)
        return try CreateWorkloadRequest(body: JSONSerialization.data(withJSONObject: body))
    }

    private let caps = Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: true)

    private func running(_ ram: Int, _ disk: Int, state: WorkloadState = .running) -> Workload {
        Workload(id: "w-\(ram)-\(disk)", name: "x", kind: .vm, state: state, cpu: 1, ramMb: ram, diskGb: disk, gpuMode: .none)
    }

    // MARK: requests

    func testCreateAcceptsAGoodBodyAndDefaults() throws {
        let request = try create()
        XCTAssertEqual(request.gpuMode, .none)
        XCTAssertNil(request.image)
        XCTAssertEqual(try create { $0["gpu_mode"] = "container"; $0["image"] = "ubuntu:24.04" }.image, "ubuntu:24.04")
    }

    func testCreateRefusesEveryBadField() {
        let bad: [(String, (inout [String: Any]) -> Void)] = [
            ("name upper", { $0["name"] = "Bad" }), ("name shell", { $0["name"] = "$(reboot)" }), ("name sql", { $0["name"] = "x'; DROP--" }),
            ("kind", { $0["kind"] = "metal" }), ("cpu 0", { $0["cpu"] = 0 }), ("cpu 65", { $0["cpu"] = 65 }), ("ram low", { $0["ram_mb"] = 511 }),
            ("disk 0", { $0["disk_gb"] = 0 }), ("disk big", { $0["disk_gb"] = 100_001 }), ("gpu mode", { $0["gpu_mode"] = "all" }),
            ("image", { $0["image"] = "Bad Image; rm" }), ("command id", { $0["command_id"] = "../x" }), ("extra", { $0["surprise"] = 1 }),
            ("cpu string", { $0["cpu"] = "2" }), ("missing name", { $0["name"] = nil }),
        ]
        for (label, change) in bad { XCTAssertThrowsError(try create(change), label) }
    }

    func testBundleInstallRequest() throws {
        let sha = String(repeating: "a", count: 64)
        let good = try BundleInstallRequest(body: JSONSerialization.data(withJSONObject: ["command_id": "c", "version": "1.2.3", "sha256": sha]))
        XCTAssertNil(good.workloadId)
        for change in [["version": "1.2"], ["sha256": "short"], ["sha256": String(repeating: "G", count: 64)], ["workload_id": "Bad Id"], ["x": 1]] as [[String: Any]] {
            var body: [String: Any] = ["command_id": "c", "version": "1.2.3", "sha256": sha]
            body.merge(change) { $1 }
            XCTAssertThrowsError(try BundleInstallRequest(body: JSONSerialization.data(withJSONObject: body)), "\(change)")
        }
    }

    // MARK: budget

    func testBudgetDefaultsAndFreeNumbers() {
        let budget = SpaceBudget(ramTotalMb: 32768, diskTotalGb: 1000, reserveRamMb: 8192, reserveDiskGb: 100, marginDiskGb: 20)
        XCTAssertEqual(budget.freeRamMb(workloads: []), 24576)
        XCTAssertEqual(budget.freeDiskGb(workloads: []), 880)
        let busy = [running(4096, 50), running(2048, 30, state: .stopped)]
        XCTAssertEqual(budget.freeRamMb(workloads: busy), 24576 - 4096, "a stopped workload holds no RAM")
        XCTAssertEqual(budget.freeDiskGb(workloads: busy), 880 - 80, "a stopped workload still holds its disk")
        let defaults = SpaceBudget(ramTotalMb: 16384, diskTotalGb: 228)
        XCTAssertEqual(defaults.reserveRamMb, 4096)
        XCTAssertEqual(defaults.reserveDiskGb, 45)
    }

    func testAllowancesCapWhatWorkloadsMayUse() {
        let budget = SpaceBudget(ramTotalMb: 65536, diskTotalGb: 2000, ramAllowanceMb: 20000, diskAllowanceGb: 300, reserveRamMb: 4000, reserveDiskGb: 50, marginDiskGb: 10)
        XCTAssertEqual(budget.freeRamMb(workloads: []), 16000)
        XCTAssertEqual(budget.freeDiskGb(workloads: []), 240)
        let oversized = SpaceBudget(ramTotalMb: 1000, diskTotalGb: 100, ramAllowanceMb: 99999, diskAllowanceGb: 99999, reserveRamMb: 0, reserveDiskGb: 0, marginDiskGb: 0)
        XCTAssertEqual(oversized.freeRamMb(workloads: []), 1000, "an allowance above the machine changes nothing")
        XCTAssertEqual(oversized.freeDiskGb(workloads: []), 100)
        let overloaded = SpaceBudget(ramTotalMb: 1000, diskTotalGb: 100, reserveRamMb: 2000, reserveDiskGb: 500, marginDiskGb: 0)
        XCTAssertEqual(overloaded.freeRamMb(workloads: []), 0, "never negative")
        XCTAssertEqual(overloaded.freeDiskGb(workloads: []), 0)
    }

    func testBudgetRefusalsCarryTheNumbers() throws {
        let budget = SpaceBudget(ramTotalMb: 10240, diskTotalGb: 200, reserveRamMb: 2048, reserveDiskGb: 40, marginDiskGb: 10)
        XCTAssertNoThrow(try budget.check(try create { $0["ram_mb"] = 8192; $0["disk_gb"] = 150 }, workloads: [], capabilities: caps, osAvailableDiskGb: nil))
        XCTAssertThrowsError(try budget.check(try create { $0["ram_mb"] = 8193 }, workloads: [], capabilities: caps, osAvailableDiskGb: nil)) {
            XCTAssertEqual($0 as? Refusal, Refusal(code: .notEnoughRoom, message: "not enough RAM", resource: .ramMb, needed: 8193, free: 8192))
        }
        XCTAssertThrowsError(try budget.check(try create { $0["disk_gb"] = 151 }, workloads: [], capabilities: caps, osAvailableDiskGb: nil)) {
            let refusal = $0 as? Refusal
            XCTAssertEqual([refusal?.resource, refusal?.needed, refusal?.free].count, 3)
            XCTAssertEqual(refusal?.resource, .diskGb)
            XCTAssertEqual(refusal?.free, 150)
        }
    }

    func testTheRealDiskCanOnlyMakeTheAnswerStricter() throws {
        let budget = SpaceBudget(ramTotalMb: 10240, diskTotalGb: 1000, reserveRamMb: 0, reserveDiskGb: 0, marginDiskGb: 20)
        let request = try create { $0["disk_gb"] = 100 }
        XCTAssertNoThrow(try budget.check(request, workloads: [], capabilities: caps, osAvailableDiskGb: 500))
        XCTAssertThrowsError(try budget.check(request, workloads: [], capabilities: caps, osAvailableDiskGb: 110)) {
            XCTAssertEqual(($0 as? Refusal)?.free, 90)
        }
    }

    func testCapabilitiesAreChecked() throws {
        let budget = SpaceBudget(ramTotalMb: 65536, diskTotalGb: 2000)
        let cases: [(String, [String: Any], Capabilities)] = [
            ("vm not supported", ["kind": "vm"], Capabilities(vm: false, container: true, gpuInVm: false, gpuInContainer: false)),
            ("container not supported", ["kind": "container"], Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false)),
            ("no gpu in vm", ["kind": "vm", "gpu_mode": "passthrough"], caps),
            ("no gpu in container", ["kind": "container", "gpu_mode": "container"], Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false)),
            ("container gpu on a vm", ["kind": "vm", "gpu_mode": "container"], Capabilities(vm: true, container: true, gpuInVm: true, gpuInContainer: true)),
        ]
        for (label, change, capabilities) in cases {
            XCTAssertThrowsError(try budget.check(try create { $0.merge(change) { $1 } }, workloads: [], capabilities: capabilities, osAvailableDiskGb: nil), label) {
                XCTAssertEqual(($0 as? Refusal)?.code, .missingCapability, label)
            }
        }
        XCTAssertNoThrow(try budget.check(try create { $0["gpu_mode"] = "container" }, workloads: [], capabilities: caps, osAvailableDiskGb: nil))
    }

    // MARK: ledger and GPU parsing

    func testLedgerKeepsCommandsAndDropsTheOldest() {
        let ledger = CommandLedger(capacity: 3)
        for index in 1...5 { ledger.record(Command(commandId: "c\(index)", type: .start, state: .succeeded)) }
        XCTAssertNil(ledger.find("c1"))
        XCTAssertNil(ledger.find("c2"))
        XCTAssertNotNil(ledger.find("c5"))
        ledger.record(Command(commandId: "c5", type: .start, state: .failed))
        XCTAssertEqual(ledger.find("c5")?.state, .failed)
        XCTAssertNotNil(ledger.find("c3"), "updating an entry does not push others out")
    }

    func testLedgerSurvivesARestartAndFailsWhatWasRunning() {
        var saved: [Command] = []
        let first = CommandLedger(persist: { saved = $0 })
        first.record(Command(commandId: "done", type: .create, state: .succeeded, workloadId: "w-1"))
        first.record(Command(commandId: "busy", type: .delete, state: .running, workloadId: "w-1"))
        let second = CommandLedger(restored: saved)
        XCTAssertEqual(second.find("done")?.state, .succeeded)
        XCTAssertEqual(second.find("busy")?.state, .failed)
        XCTAssertEqual(second.find("busy")?.result?["error"], "the Agent restarted before this finished")
        XCTAssertNil(second.find("nope"))
    }

    func testGpuParsing() {
        let json = Data("""
        {"SPDisplaysDataType":[{"sppci_model":"Apple M2 Pro","spdisplays_vendor":"sppci_vendor_Apple"},
        {"sppci_model":"Radeon Pro 5500M","sppci_vendor":"sppci_vendor_amd","spdisplays_vram":"8 GB"},{"sppci_model":""},{"x":1}]}
        """.utf8)
        let gpus = GpuParser.parse(json)
        XCTAssertEqual(gpus.map(\.model), ["Apple M2 Pro", "Radeon Pro 5500M"])
        XCTAssertEqual(gpus[1], Gpu(vendor: "amd", model: "Radeon Pro 5500M", memoryMb: 8192))
        XCTAssertTrue(GpuParser.parse(Data("junk".utf8)).isEmpty)
    }

    func testFactsAndWorkloadsEncodeLikeTheContract() throws {
        let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, ramTotalMb: 32768, diskTotalGb: 1000, gpu: [Gpu(vendor: "apple", model: "M2", memoryMb: nil)])
        let facts = Facts(specs: specs, freeRamMb: 1, freeDiskGb: 2, capabilities: Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try JSONSerialization.jsonObject(with: encoder.encode(facts)) as! [String: Any]
        XCTAssertEqual(Set(object.keys), ["os", "arch", "cpu_cores", "ram_total_mb", "disk_total_gb", "free_ram_mb", "free_disk_gb", "gpu", "capabilities"])
        XCTAssertEqual(Set((object["capabilities"] as! [String: Any]).keys), ["vm", "container", "gpu_in_vm", "gpu_in_container"])
        let workload = try JSONSerialization.jsonObject(with: encoder.encode(running(512, 1))) as! [String: Any]
        XCTAssertTrue(workload["address"] is NSNull && workload["bundle_version"] is NSNull)
    }
}
