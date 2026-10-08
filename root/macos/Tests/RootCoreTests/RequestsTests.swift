import XCTest
@testable import RootCore

final class RequestsTests: XCTestCase {
    private func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    func testEnrollAcceptsAGoodBody() throws {
        let request = try EnrollRequest(body: data(["enrollment_token": String(repeating: "a", count: 43), "name": "mac-mini"]))
        XCTAssertEqual(request.name, "mac-mini")
    }

    func testEnrollRejectsBadBodies() {
        let token = String(repeating: "a", count: 43)
        let bad: [Any] = [
            ["enrollment_token": "short", "name": "ok"], ["enrollment_token": token, "name": "Bad Name"],
            ["enrollment_token": token, "name": "ok", "extra": 1], ["enrollment_token": token], ["name": "ok"],
            ["enrollment_token": 12345678901234567, "name": "ok"], ["enrollment_token": token, "name": ["a"]],
            ["enrollment_token": String(repeating: "a", count: 257), "name": "ok"], [1, 2, 3],
        ]
        for item in bad { XCTAssertThrowsError(try EnrollRequest(body: data(item)), "\(item)") }
        for raw in ["", "{", "null", "[]", "\"text\""] { XCTAssertThrowsError(try EnrollRequest(body: Data(raw.utf8)), raw) }
    }

    static func goodHeartbeat() -> [String: Any] {
        [
            "facts": [
                "os": "linux", "arch": "aarch64", "cpu_cores": 20, "ram_total_mb": 131072, "disk_total_gb": 3800,
                "free_ram_mb": 100000, "free_disk_gb": 3000,
                "gpu": [["vendor": "nvidia", "model": "GB10", "memory_mb": 131072]],
                "capabilities": ["vm": true, "container": true, "gpu_in_vm": false, "gpu_in_container": true],
            ],
            "workloads": [[
                "id": "wl-1", "name": "demo", "kind": "container", "state": "running", "cpu": 2, "ram_mb": 2048, "disk_gb": 20,
                "gpu_mode": "container", "address": NSNull(), "bundle_version": "1.0.0",
            ]],
            "bundle_version": "1.0.0",
        ]
    }

    func testHeartbeatAcceptsAGoodBody() throws {
        let beat = try HeartbeatRequest(body: data(Self.goodHeartbeat()))
        XCTAssertEqual(beat.facts.arch, "aarch64")
        XCTAssertEqual(beat.workloads.count, 1)
        XCTAssertNil(beat.workloads[0].address)
        XCTAssertEqual(beat.facts.gpu.first?.memoryMb, 131072)
    }

    func testHeartbeatRejectsEachBrokenField() {
        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("unknown top field", { $0["extra"] = 1 }),
            ("no facts", { $0["facts"] = nil }),
            ("os value", { var f = $0["facts"] as! [String: Any]; f["os"] = "plan9"; $0["facts"] = f }),
            ("cpu as bool", { var f = $0["facts"] as! [String: Any]; f["cpu_cores"] = true; $0["facts"] = f }),
            ("cpu as float", { var f = $0["facts"] as! [String: Any]; f["cpu_cores"] = 1.5; $0["facts"] = f }),
            ("negative free ram", { var f = $0["facts"] as! [String: Any]; f["free_ram_mb"] = -1; $0["facts"] = f }),
            ("caps not bool", { var f = $0["facts"] as! [String: Any]; f["capabilities"] = ["vm": 1, "container": true, "gpu_in_vm": false, "gpu_in_container": false]; $0["facts"] = f }),
            ("workload id", { var w = $0["workloads"] as! [[String: Any]]; w[0]["id"] = "Bad Id"; $0["workloads"] = w }),
            ("workload state", { var w = $0["workloads"] as! [[String: Any]]; w[0]["state"] = "exploded"; $0["workloads"] = w }),
            ("workload extra", { var w = $0["workloads"] as! [[String: Any]]; w[0]["root"] = true; $0["workloads"] = w }),
            ("bundle version", { $0["bundle_version"] = "latest" }),
            ("too many workloads", { $0["workloads"] = (0..<1001).map { ["id": "w\($0)"] } }),
        ]
        for (label, change) in mutations {
            var body = Self.goodHeartbeat()
            change(&body)
            XCTAssertThrowsError(try HeartbeatRequest(body: data(body)), label)
        }
    }

    func testStrictObjectTellsBoolFromNumber() throws {
        let object = try StrictObject(data: data(["flag": true, "count": 1]), allowed: ["flag", "count"])
        XCTAssertNoThrow(try object.bool("flag"))
        XCTAssertThrowsError(try object.bool("count"))
        XCTAssertThrowsError(try object.int("flag", range: 0...5))
        XCTAssertEqual(try object.int("count", range: 0...5), 1)
        XCTAssertThrowsError(try object.int("count", range: 2...5))
    }
}
