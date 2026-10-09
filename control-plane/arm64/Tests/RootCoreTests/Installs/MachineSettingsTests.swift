import XCTest
@testable import RootCore

final class MachineSettingsTests: XCTestCase {
    private func request(_ extra: [String: Any]) throws -> InstallRequest {
        try InstallRequest(body: JSONSerialization.data(withJSONObject: ["target": "this", "name": "mini", "chat": false].merging(extra) { $1 }))
    }

    func testEverySettingIsReadAndTheDefaultsAreQuiet() throws {
        let bare = try request([:]).settings
        XCTAssertEqual(bare, MachineSettings())
        XCTAssertTrue(bare.allowGpu)
        XCTAssertFalse(bare.publicChat)
        let full = try request(["profile": "gpu-box", "labels": ["office", "gpu"], "notes": "under the desk", "ram_reserve_mb": 4096, "disk_reserve_gb": 30, "ram_allowance_mb": 65536,
                                "disk_allowance_gb": 900, "allow_gpu": false, "vm_cpu": 4, "vm_ram_mb": 8192, "vm_disk_gb": 60, "vm_image": "images:ubuntu/24.04",
                                "vm_max_running": 6, "subdomain": "dgx1", "public_chat": true, "ai_model": "anthropic/claude-sonnet-5"]).settings
        XCTAssertEqual([full.profile, full.labels.joined(separator: ","), full.notes, full.subdomain, full.aiModel, full.vmImage], ["gpu-box", "office,gpu", "under the desk", "dgx1", "anthropic/claude-sonnet-5", "images:ubuntu/24.04"])
        XCTAssertEqual([full.ramReserveMb, full.diskReserveGb, full.ramAllowanceMb, full.diskAllowanceGb, full.vmCpu, full.vmRamMb, full.vmDiskGb, full.vmMaxRunning], [4096, 30, 65536, 900, 4, 8192, 60, 6])
        XCTAssertFalse(full.allowGpu)
        XCTAssertTrue(full.publicChat)
    }

    func testEveryOddSettingIsRefused() {
        let bad: [(String, [String: Any])] = [
            ("profile", ["profile": "toaster"]), ("label shape", ["labels": ["Has Space"]]), ("label twice", ["labels": ["a", "a"]]), ("too many labels", ["labels": (0..<9).map { "l\($0)" }]),
            ("labels as text", ["labels": "office"]), ("long notes", ["notes": String(repeating: "x", count: 301)]), ("ram allowance too small", ["ram_allowance_mb": 100]),
            ("reserve not below allowance", ["ram_reserve_mb": 8192, "ram_allowance_mb": 4096]), ("disk reserve not below allowance", ["disk_reserve_gb": 100, "disk_allowance_gb": 100]),
            ("cpu zero", ["vm_cpu": 0]), ("cpu huge", ["vm_cpu": 65]), ("ram tiny", ["vm_ram_mb": 100]), ("max running zero", ["vm_max_running": 0]),
            ("image with a flag", ["vm_image": "--privileged"]), ("subdomain with a dot", ["subdomain": "a.b"]), ("subdomain upper", ["subdomain": "Mac1"]),
            ("model with a space", ["ai_model": "my model"]), ("gpu as text", ["allow_gpu": "no"]), ("public chat as number", ["public_chat": 1]),
        ]
        for (label, extra) in bad { XCTAssertThrowsError(try request(extra), label) }
    }

    func testSwitchingTheGpuOffHidesItAndTheMaximumStopsNewVMs() {
        let all = Capabilities(vm: true, container: true, gpuInVm: true, gpuInContainer: true)
        XCTAssertEqual(MachineSettings(allowGpu: true).limiting(all), all)
        XCTAssertEqual(MachineSettings(allowGpu: false).limiting(all), Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false))
        XCTAssertNil(MachineSettings(allowGpu: false).limiting(nil))
        let capped = MachineSettings(vmMaxRunning: 2)
        XCTAssertFalse(capped.isFull(running: 1))
        XCTAssertTrue(capped.isFull(running: 2))
        XCTAssertTrue(capped.isFull(running: 5))
        XCTAssertFalse(MachineSettings().isFull(running: 1000), "no maximum means no limit")
    }
}
