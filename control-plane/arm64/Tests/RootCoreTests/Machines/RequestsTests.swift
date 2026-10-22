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

    private func beat(stopped change: (inout [String: Any]) -> Void) throws -> WorkloadReport {
        var body = Self.goodHeartbeat()
        var workloads = body["workloads"] as! [[String: Any]]
        workloads[0]["state"] = "stopped"
        change(&workloads[0])
        body["workloads"] = workloads
        return try HeartbeatRequest(body: data(body)).workloads[0]
    }

    func testAStoppedWorkloadCarriesItsReasonAndHowItCameUp() throws {
        let report = try beat { $0["stopped_reason"] = ["exit_code": 255, "log_tail": "Exiting PID 1...\nstatus 255"]; $0["init_mode"] = "plain" }
        XCTAssertEqual(report.stoppedReason, StoppedReasonReport(exitCode: 255, logTail: "Exiting PID 1...\nstatus 255"))
        XCTAssertEqual(report.initMode, "plain")
        XCTAssertNil(try beat { $0["stopped_reason"] = ["exit_code": NSNull(), "log_tail": "x"] }.stoppedReason?.exitCode)
        XCTAssertNil(try beat { _ in }.stoppedReason, "the field is optional")
        XCTAssertNil(try beat { $0["stopped_reason"] = NSNull() }.stoppedReason)
    }

    func testAReasonOnAWorkloadThatIsNotStoppedIsDropped() throws {
        var body = Self.goodHeartbeat()
        var workloads = body["workloads"] as! [[String: Any]]
        workloads[0]["stopped_reason"] = ["exit_code": 1, "log_tail": "old news"]
        body["workloads"] = workloads
        XCTAssertNil(try HeartbeatRequest(body: data(body)).workloads[0].stoppedReason, "a running workload has no reason")
    }

    func testTheReasonTextIsCleanedAndCappedAgain() throws {
        let hostile = "\u{1B}[31m<img src=x onerror=alert(1)>\u{1B}]0;t\u{07}\u{00}\n" + (1...40).map { "line \($0)" }.joined(separator: "\n") + "\n" + String(repeating: "é", count: 5000)
        let tail = try XCTUnwrap(try beat { $0["stopped_reason"] = ["exit_code": 1, "log_tail": hostile] }.stoppedReason?.logTail)
        XCTAssertLessThanOrEqual(tail.utf8.count, 2048)
        XCTAssertFalse(tail.contains("\u{1B}") || tail.contains("\u{00}") || tail.contains("\u{07}"))
        XCTAssertLessThanOrEqual(tail.split(separator: "\n").count, 12)
        let markup = try XCTUnwrap(try beat { $0["stopped_reason"] = ["exit_code": 1, "log_tail": "<b>x</b>"] }.stoppedReason?.logTail)
        XCTAssertEqual(markup, "<b>x</b>", "markup is kept as the same text; the panel shows it as text")
    }

    func testBrokenReasonsAndModesAreRefused() {
        let bad: [(String, (inout [String: Any]) -> Void)] = [
            ("extra key", { $0["stopped_reason"] = ["exit_code": 1, "log_tail": "x", "more": 1] }),
            ("no log tail", { $0["stopped_reason"] = ["exit_code": 1] }),
            ("log tail number", { $0["stopped_reason"] = ["exit_code": 1, "log_tail": 5] }),
            ("exit code text", { $0["stopped_reason"] = ["exit_code": "1", "log_tail": "x"] }),
            ("exit code huge", { $0["stopped_reason"] = ["exit_code": 99999, "log_tail": "x"] }),
            ("huge text", { $0["stopped_reason"] = ["exit_code": 1, "log_tail": String(repeating: "x", count: 20_001)] }),
            ("reason as text", { $0["stopped_reason"] = "boom" }),
            ("init mode", { $0["init_mode"] = "docker" }),
        ]
        for (label, change) in bad { XCTAssertThrowsError(try beat(stopped: change), label) }
    }

    func testHostProblemsAreReadAndDefaultToNone() throws {
        XCTAssertEqual(try HeartbeatRequest(body: data(Self.goodHeartbeat())).facts.problems, [])
        var body = Self.goodHeartbeat()
        var facts = body["facts"] as! [String: Any]
        facts["problems"] = [["code": "bridge_blocked_by_firewall", "message": "VMs get no IPv4", "fix": "Run setup"]]
        body["facts"] = facts
        XCTAssertEqual(try HeartbeatRequest(body: data(body)).facts.problems, [HostProblem(code: "bridge_blocked_by_firewall", message: "VMs get no IPv4", fix: "Run setup")])
    }

    func testBrokenHostProblemsAreRefused() {
        let bad: [Any] = [
            [["code": "Bad Code", "message": "m", "fix": "f"]], [["code": "ok", "message": "", "fix": "f"]], [["code": "ok", "message": "m"]],
            [["code": "ok", "message": "m", "fix": "f", "extra": 1]], [["code": "ok", "message": String(repeating: "x", count: 301), "fix": "f"]],
            [["code": "ok", "message": "m", "fix": String(repeating: "x", count: 501)]], "text", (0..<21).map { _ in ["code": "ok", "message": "m", "fix": "f"] },
        ]
        for item in bad {
            var body = Self.goodHeartbeat()
            var facts = body["facts"] as! [String: Any]
            facts["problems"] = item
            body["facts"] = facts
            XCTAssertThrowsError(try HeartbeatRequest(body: data(body)), "\(item)")
        }
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

}

final class LocalMachineNameTests: XCTestCase {
    func testAHostNameBecomesAValidMachineName() {
        XCTAssertEqual(LocalMachineName.make(from: "MacBook-Pro-mac.local"), "macbook-pro-mac")
        XCTAssertEqual(LocalMachineName.make(from: "Kurnia's MacBook Pro"), "kurnia-s-macbook-pro")
        XCTAssertEqual(LocalMachineName.make(from: "mac-studio"), "mac-studio")
        XCTAssertEqual(LocalMachineName.make(from: "dgx.spark.lan"), "dgx")
    }

    func testOddHostNamesFallBackAndNeverBreakTheRules() {
        for odd in ["", ".", "---", "...", "日本語", "-", " "] { XCTAssertEqual(LocalMachineName.make(from: odd), LocalMachineName.fallback, odd) }
        let long = LocalMachineName.make(from: String(repeating: "a", count: 200))
        XCTAssertTrue(long.count <= 63 && Ids.isValid(long))
        XCTAssertTrue(Ids.isValid(LocalMachineName.make(from: "-Weird_Name--")))
    }
}
