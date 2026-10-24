import XCTest
@testable import RootCore

final class SandboxFactsTests: XCTestCase {
    private static let goodFacts: [String: Any] = [
        "engine": ["name": "firecracker", "version": "1.7.0"],
        "max_running": 20, "running": 2, "paused": 1,
        "max_vcpu": 8, "max_ram_mb": 16384, "max_disk_mb": 102400,
        "booked": ["vcpu": 4, "ram_mb": 4096, "disk_mb": 20480],
        "templates": [["id": "base", "build": "b1", "ready": true]],
        "changes": 7,
    ]

    private func heartbeat(capabilities: [String: Any] = [:], facts: Any?) throws -> HeartbeatRequest {
        var caps: [String: Any] = ["vm": false, "container": false, "gpu_in_vm": false, "gpu_in_container": false]
        caps.merge(capabilities) { $1 }
        var reported: [String: Any] = ["os": "linux", "arch": "x86_64", "cpu_cores": 8, "ram_total_mb": 65536, "disk_total_gb": 1000,
                                       "free_ram_mb": 60000, "free_disk_gb": 900, "gpu": [], "capabilities": caps]
        if let facts { reported["sandbox"] = facts }
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: ["facts": reported, "workloads": []]))
    }

    func testTheHelperSaysSandboxAndAbsentReadsAsFalse() throws {
        XCTAssertTrue(try heartbeat(capabilities: ["sandbox": true], facts: Self.goodFacts).facts.capabilities.sandbox)
        XCTAssertFalse(try heartbeat(capabilities: ["sandbox": false], facts: nil).facts.capabilities.sandbox)
        XCTAssertFalse(try heartbeat(facts: nil).facts.capabilities.sandbox, "an older helper does not say it")
    }

    func testABrokenSandboxCapabilityIsRefused() {
        for value in ["yes", 1, ["on"]] { XCTAssertThrowsError(try heartbeat(capabilities: ["sandbox": value], facts: nil), "\(value)") }
    }

    func testTheSandboxFactsAreReadAsReported() throws {
        let facts = try XCTUnwrap(try heartbeat(capabilities: ["sandbox": true], facts: Self.goodFacts).facts.sandbox)
        XCTAssertEqual(facts.engine, SandboxFacts.Engine(name: "firecracker", version: "1.7.0"))
        XCTAssertEqual([facts.maxRunning, facts.running, facts.paused], [20, 2, 1])
        XCTAssertEqual([facts.maxVcpu, facts.maxRamMb, facts.maxDiskMb], [8, 16384, 102400])
        XCTAssertEqual(facts.booked, SandboxFacts.Booking(vcpu: 4, ramMb: 4096, diskMb: 20480))
        XCTAssertEqual(facts.templates, [SandboxFacts.Template(id: "base", build: "b1", ready: true)])
        XCTAssertEqual(facts.changes, 7)
    }

    func testAnEngineWithoutAVersionReadsAsNullAndIsSentAsNull() throws {
        var reported = Self.goodFacts
        reported["engine"] = ["name": "firecracker"]
        let facts = try XCTUnwrap(try heartbeat(capabilities: ["sandbox": true], facts: reported).facts.sandbox)
        XCTAssertNil(facts.engine.version)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(facts)) as! [String: Any]
        XCTAssertTrue((json["engine"] as! [String: Any])["version"] is NSNull)
    }

    func testTheSimulatedEngineIsAcceptedSoATruthfulTestHelperPasses() throws {
        var reported = Self.goodFacts
        reported["engine"] = ["name": "simulated"]
        let facts = try XCTUnwrap(try heartbeat(capabilities: ["sandbox": true], facts: reported).facts.sandbox)
        XCTAssertEqual(facts.engine.name, "simulated")
    }

    func testAnUnknownEngineIsStillRefused() {
        var reported = Self.goodFacts
        reported["engine"] = ["name": "qemu"]
        XCTAssertThrowsError(try heartbeat(capabilities: ["sandbox": true], facts: reported))
    }

    func testFactsFromAHelperThatSaysItCannotRunSandboxesAreDropped() throws {
        XCTAssertNil(try heartbeat(capabilities: ["sandbox": false], facts: Self.goodFacts).facts.sandbox)
        XCTAssertNil(try heartbeat(facts: Self.goodFacts).facts.sandbox, "no capability means no sandboxes, whatever the facts say")
    }

    func testBrokenSandboxFactsAreRefused() {
        var cases: [(String, Any)] = [("not an object", "sandbox"), ("a list", [1, 2])]
        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("unknown key", { $0["extra"] = 1 }),
            ("no engine", { $0["engine"] = nil }),
            ("engine not an object", { $0["engine"] = "firecracker" }),
            ("wrong engine", { $0["engine"] = ["name": "qemu", "version": "1.0"] }),
            ("engine extra key", { $0["engine"] = ["name": "firecracker", "version": "1.0", "ready": true] }),
            ("bad version", { $0["engine"] = ["name": "firecracker", "version": "1.0 / bad"] }),
            ("no running", { $0["running"] = nil }),
            ("negative running", { $0["running"] = -1 }),
            ("running as text", { $0["running"] = "2" }),
            ("no max vcpu", { $0["max_vcpu"] = nil }),
            ("zero max vcpu", { $0["max_vcpu"] = 0 }),
            ("small max ram", { $0["max_ram_mb"] = 255 }),
            ("small max disk", { $0["max_disk_mb"] = 511 }),
            ("booked not an object", { $0["booked"] = [4, 4096, 20480] }),
            ("booked missing disk", { $0["booked"] = ["vcpu": 4, "ram_mb": 4096] }),
            ("booked extra key", { $0["booked"] = ["vcpu": 4, "ram_mb": 4096, "disk_mb": 20480, "gpu": 1] }),
            ("templates not a list", { $0["templates"] = "base" }),
            ("template without ready", { $0["templates"] = [["id": "base", "build": "b1"]] }),
            ("bad template id", { $0["templates"] = [["id": "Base Image", "build": "b1", "ready": true]] }),
            ("bad build", { $0["templates"] = [["id": "base", "build": "Build/1", "ready": true]] }),
            ("too many templates", { $0["templates"] = (0..<65).map { ["id": "t\($0)", "build": "b1", "ready": true] } }),
            ("no changes", { $0["changes"] = nil }),
            ("negative changes", { $0["changes"] = -1 }),
        ]
        for (label, change) in mutations {
            var facts = Self.goodFacts
            change(&facts)
            cases.append((label, facts))
        }
        for (label, facts) in cases { XCTAssertThrowsError(try heartbeat(capabilities: ["sandbox": true], facts: facts), label) }
    }

    func testCapabilitiesSavedByAnOlderParentReadAsNoSandboxes() throws {
        let old = Data(#"{"vm":true,"container":false,"gpuInVm":false,"gpuInContainer":false}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Capabilities.self, from: old).sandbox)
        let saved = try JSONDecoder().decode(Capabilities.self, from: JSONEncoder().encode(Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false, sandbox: true)))
        XCTAssertTrue(saved.sandbox)
    }
}
