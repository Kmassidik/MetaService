import XCTest
@testable import RootCore

final class TerminalCapabilityTests: XCTestCase {
    private func heartbeat(capabilities: [String: Any] = [:]) throws -> HeartbeatRequest {
        var caps: [String: Any] = ["vm": false, "container": true, "gpu_in_vm": false, "gpu_in_container": false]
        caps.merge(capabilities) { $1 }
        let facts: [String: Any] = ["os": "linux", "arch": "x86_64", "cpu_cores": 8, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 60000, "free_disk_gb": 900,
                                    "gpu": [], "capabilities": caps]
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: ["facts": facts, "workloads": []]))
    }

    func testTheHelperSaysTerminalAndOldHelpersReadAsNotSaying() throws {
        XCTAssertTrue(try heartbeat(capabilities: ["terminal": true]).facts.capabilities.terminal)
        XCTAssertFalse(try heartbeat(capabilities: ["terminal": false]).facts.capabilities.terminal)
        XCTAssertFalse(try heartbeat().facts.capabilities.terminal)
        XCTAssertThrowsError(try heartbeat(capabilities: ["terminal": "yes"]))
    }
}
