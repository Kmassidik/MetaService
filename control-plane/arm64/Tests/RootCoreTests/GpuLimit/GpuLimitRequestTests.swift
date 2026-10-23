import XCTest
@testable import RootCore

final class GpuLimitRequestTests: XCTestCase {
    private func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    private func create(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> CreateWorkloadOperatorRequest {
        var body: [String: Any] = ["name": "demo", "kind": "container", "cpu": 2, "ram_mb": 2048, "disk_gb": 20, "gpu_mode": "container"]
        change(&body)
        return try CreateWorkloadOperatorRequest(body: data(body))
    }

    func testALimitIsReadWithTheContainerGpuMode() throws {
        XCTAssertEqual(try create { $0["gpu_memory_gb"] = 4 }.gpuMemoryGb, 4)
        XCTAssertEqual(try create { $0["gpu_memory_gb"] = 1 }.gpuMemoryGb, 1)
        XCTAssertEqual(try create { $0["gpu_memory_gb"] = 1024 }.gpuMemoryGb, 1024)
        XCTAssertNil(try create().gpuMemoryGb, "no limit asks for the whole card shared")
        XCTAssertNil(try create { $0["gpu_memory_gb"] = NSNull() }.gpuMemoryGb)
    }

    func testALimitOutsideOneToAThousandAndTwentyFourOrNotAWholeNumberIsRefused() {
        for bad: Any in [0, -1, 1025, 4.5, "4", true] {
            XCTAssertThrowsError(try create { $0["gpu_memory_gb"] = bad }, "\(bad)")
        }
    }

    func testALimitWithoutTheContainerGpuModeIsRefusedInPlainWords() {
        for mode in ["none", "passthrough"] {
            XCTAssertThrowsError(try create { $0["gpu_mode"] = mode; $0["gpu_memory_gb"] = 4 }) {
                XCTAssertEqual(($0 as? InputError)?.message, "gpu_memory_gb can only be set when gpu_mode is container")
            }
        }
        XCTAssertThrowsError(try create { $0.removeValue(forKey: "gpu_mode"); $0["gpu_memory_gb"] = 4 })
    }

    func testTheLimitSurvivesPlacingTheRequestOnAMachine() throws {
        XCTAssertEqual(try create { $0["gpu_memory_gb"] = 4 }.placed(on: "dgx").gpuMemoryGb, 4)
    }

    func testTheHelperCreateBodyCarriesTheLimitOnlyWhenThereIsOne() throws {
        let with = HelperCreateBody.make(commandId: "rc-1", request: try create { $0["gpu_memory_gb"] = 4 }, machineDefaultImage: nil)
        XCTAssertEqual(with["gpu_memory_gb"] as? Int, 4)
        let without = HelperCreateBody.make(commandId: "rc-1", request: try create(), machineDefaultImage: nil)
        XCTAssertNil(without["gpu_memory_gb"])
    }

    private func heartbeat(capabilities: [String: Any] = [:], workload: [String: Any] = [:]) throws -> HeartbeatRequest {
        var caps: [String: Any] = ["vm": false, "container": true, "gpu_in_vm": false, "gpu_in_container": true]
        caps.merge(capabilities) { $1 }
        var item: [String: Any] = ["id": "wl-1", "name": "demo", "kind": "container", "state": "running", "cpu": 2, "ram_mb": 2048, "disk_gb": 20, "gpu_mode": "container"]
        item.merge(workload) { $1 }
        let facts: [String: Any] = ["os": "linux", "arch": "x86_64", "cpu_cores": 8, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 60000, "free_disk_gb": 900,
                                    "gpu": [["vendor": "nvidia", "model": "RTX", "memory_mb": 32607]], "capabilities": caps]
        return try HeartbeatRequest(body: data(["facts": facts, "workloads": [item]]))
    }

    func testTheHelperAnnouncesTheLimitAndOldHelpersReadAsNotAnnouncing() throws {
        XCTAssertTrue(try heartbeat(capabilities: ["gpu_memory_limit": true]).facts.capabilities.gpuMemoryLimit)
        XCTAssertFalse(try heartbeat(capabilities: ["gpu_memory_limit": false]).facts.capabilities.gpuMemoryLimit)
        XCTAssertFalse(try heartbeat().facts.capabilities.gpuMemoryLimit)
        XCTAssertThrowsError(try heartbeat(capabilities: ["gpu_memory_limit": "yes"]))
    }

    func testSavedCapabilitiesFromBeforeTheFeatureStillRead() throws {
        let old = Data(#"{"vm":true,"container":true,"gpuInVm":false,"gpuInContainer":true}"#.utf8)
        let caps = try JSONDecoder().decode(Capabilities.self, from: old)
        XCTAssertTrue(caps.gpuInContainer)
        XCTAssertFalse(caps.gpuMemoryLimit)
    }

    func testAWorkloadReportCarriesItsLimitWithinRange() throws {
        XCTAssertEqual(try heartbeat(workload: ["gpu_memory_gb": 4]).workloads[0].gpuMemoryGb, 4)
        XCTAssertNil(try heartbeat(workload: ["gpu_memory_gb": NSNull()]).workloads[0].gpuMemoryGb)
        XCTAssertNil(try heartbeat().workloads[0].gpuMemoryGb)
        for bad: Any in [0, 1025, 1.5, "4"] { XCTAssertThrowsError(try heartbeat(workload: ["gpu_memory_gb": bad]), "\(bad)") }
    }

    // MARK: the stopped reason from the watchdog

    private func reason(_ fields: [String: Any]) throws -> StoppedReasonReport? {
        try heartbeat(workload: ["state": "stopped", "stopped_reason": fields]).workloads[0].stoppedReason
    }

    func testAWatchdogReasonKeepsItsCodeMessageAndNumbers() throws {
        let kept = try XCTUnwrap(reason(["code": "gpu_memory_over_limit", "message": "It used 5.5 GB; the limit is 4 GB.", "used_gb": 5.5, "limit_gb": 4]))
        XCTAssertEqual(kept, StoppedReasonReport(exitCode: nil, logTail: "", code: "gpu_memory_over_limit", message: "It used 5.5 GB; the limit is 4 GB.", usedGb: 5.5, limitGb: 4))
    }

    func testBothShapesAreAccepted() throws {
        XCTAssertEqual(try reason(["exit_code": 1]), StoppedReasonReport(exitCode: 1, logTail: ""))
        XCTAssertEqual(try reason(["exit_code": 1, "log_tail": "x"]), StoppedReasonReport(exitCode: 1, logTail: "x"))
        XCTAssertThrowsError(try reason(["log_tail": 5]))
    }

    func testTheReasonMessageIsCleanedAndCappedAndNumbersAreChecked() throws {
        let hostile = "\u{1B}[31m<b>red</b>\u{1B}[0m\u{00}" + String(repeating: "é", count: 5000)
        let kept = try XCTUnwrap(reason(["code": "gpu_memory_over_limit", "message": hostile]))
        let message = try XCTUnwrap(kept.message)
        XCTAssertFalse(message.contains("\u{1B}") || message.contains("\u{00}"))
        XCTAssertLessThanOrEqual(message.utf8.count, StoppedReasonReport.maxMessageBytes)
        for bad in [["code": "Bad Code!"], ["code": ""], ["code": "ok", "used_gb": -1], ["code": "ok", "used_gb": "5"], ["code": "ok", "limit_gb": true], ["code": "ok", "extra": 1]] as [[String: Any]] {
            XCTAssertThrowsError(try reason(bad), "\(bad)")
        }
    }

    func testTheReasonIsStoredAndReadBackAndOldSavedReasonsStillRead() throws {
        let original = StoppedReasonReport(exitCode: nil, logTail: "", code: "gpu_memory_over_limit", message: "m", usedGb: 5.5, limitGb: 4)
        XCTAssertEqual(try JSONDecoder().decode(StoppedReasonReport.self, from: JSONEncoder().encode(original)), original)
        let old = try JSONDecoder().decode(StoppedReasonReport.self, from: Data(#"{"exitCode":255,"logTail":"x"}"#.utf8))
        XCTAssertEqual(old, StoppedReasonReport(exitCode: 255, logTail: "x"))
    }

    // MARK: placement

    private func machine(_ id: String, room: GpuRoom, ram: Int = 8192) -> PlacementMachine {
        PlacementMachine(id: id, online: true, capabilities: Capabilities(vm: false, container: true, gpuInVm: false, gpuInContainer: true), freeRamMb: ram, freeDiskGb: 500, gpuRoom: room)
    }

    private func wish(_ gb: Int?) -> PlacementWish {
        PlacementWish(kind: "container", gpuMode: "container", ramMb: 1024, diskGb: 10, onlyMachine: nil, gpuMemoryGb: gb)
    }

    func testAPlacementSkipsMachinesWhereTheLimitDoesNotFit() throws {
        let full = machine("big", room: GpuRoom(announcesLimit: true, totalGb: 8, bookedGb: 8), ram: 99999)
        let open = machine("small", room: GpuRoom(announcesLimit: true, totalGb: 8, bookedGb: 2), ram: 4096)
        XCTAssertEqual(try Placement.choose([full, open], wish(4)), "small")
        XCTAssertEqual(try Placement.choose([full, open], wish(nil)), "big", "no limit asked: the booking is not looked at")
    }

    func testWhenNoMachineCanBookTheFirstMachinesReasonIsTheAnswer() {
        let full = machine("b", room: GpuRoom(announcesLimit: true, totalGb: 8, bookedGb: 8))
        let old = machine("a", room: GpuRoom(announcesLimit: false, totalGb: 8, bookedGb: 0))
        XCTAssertThrowsError(try Placement.choose([full, old], wish(4))) { XCTAssertEqual(($0 as? GpuBookingRefusal)?.code, "helper_too_old") }
        XCTAssertThrowsError(try Placement.choose([full], wish(4))) { XCTAssertEqual(($0 as? GpuBookingRefusal)?.freeGb, 0) }
    }
}
