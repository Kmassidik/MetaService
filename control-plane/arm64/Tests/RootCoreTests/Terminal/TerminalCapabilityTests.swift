import XCTest
@testable import RootCore

/// The Linux helper says `terminal: true` in its capabilities since it serves the console route. A heartbeat with it must be taken, or the machine shows offline.
final class TerminalCapabilityTests: XCTestCase {
    private func heartbeat(capabilities: [String: Any]) throws -> HeartbeatRequest {
        var caps: [String: Any] = ["vm": true, "container": true, "gpu_in_vm": false, "gpu_in_container": false]
        caps.merge(capabilities) { $1 }
        let facts: [String: Any] = ["os": "linux", "arch": "x86_64", "cpu_cores": 8, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 60000, "free_disk_gb": 900,
                                    "gpu": [], "capabilities": caps]
        return try HeartbeatRequest(body: try JSONSerialization.data(withJSONObject: ["facts": facts, "workloads": []]))
    }

    func testAHeartbeatThatSaysTerminalIsTaken() {
        XCTAssertNoThrow(try heartbeat(capabilities: ["terminal": true]))
        XCTAssertNoThrow(try heartbeat(capabilities: ["terminal": false]))
        XCTAssertNoThrow(try heartbeat(capabilities: [:]))
    }

    func testATerminalThatIsNotTrueOrFalseIsRefused() {
        for bad: Any in ["yes", 1] {
            XCTAssertThrowsError(try heartbeat(capabilities: ["terminal": bad]), "\(bad)")
        }
    }
}
