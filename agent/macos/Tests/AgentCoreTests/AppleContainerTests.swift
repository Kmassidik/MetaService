import XCTest
@testable import AgentCore

final class AppleContainerTests: XCTestCase {
    private func request(_ change: ((inout [String: Any]) -> Void)? = nil) throws -> CreateWorkloadRequest {
        var body: [String: Any] = ["command_id": "c-1", "name": "demo", "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 10]
        change?(&body)
        return try CreateWorkloadRequest(body: JSONSerialization.data(withJSONObject: body))
    }

    func testRunArgumentsAreOneFixedShape() throws {
        let args = AppleContainer.run(id: "w-abc", request: try request(), image: "docker.io/library/ubuntu:24.04")
        XCTAssertEqual(Array(args.prefix(10)), ["run", "--detach", "--name", "ms-w-abc", "--cpus", "2", "--memory", "2048M", "--label", "metaservice.id=w-abc"])
        XCTAssertEqual(args[10], "docker.io/library/ubuntu:24.04")
        XCTAssertEqual(Array(args[11...12]), ["sh", "-c"])
        XCTAssertEqual(args.last, AppleContainer.initScript)
        XCTAssertEqual(args.count, 14, "no extra flags such as capabilities, mounts or ports")
    }

    func testNoUserTextCanBecomeAFlag() throws {
        for hostile in ["demo", "a-b"] {
            let args = AppleContainer.run(id: "w-x", request: try request { $0["name"] = hostile }, image: "ubuntu:24.04")
            XCTAssertFalse(args.contains(hostile), "the user's name is only a label in MetaService, never passed to the tool")
        }
        let image = try request { $0["image"] = "ubuntu:24.04" }
        XCTAssertEqual(image.image, "ubuntu:24.04")
        for bad in ["--privileged", "-v /:/host", "ubuntu; reboot", "../x", "A B", "-x"] {
            XCTAssertThrowsError(try request { $0["image"] = bad }, bad)
        }
    }

    func testOtherCommands() {
        XCTAssertEqual(AppleContainer.stop("w-1"), ["stop", "--signal", "SIGRTMIN+3", "--time", "30", "ms-w-1"])
        XCTAssertEqual(AppleContainer.delete("w-1"), ["delete", "--force", "ms-w-1"])
        XCTAssertEqual(AppleContainer.export("w-1", to: "/b/x.tar"), ["export", "--output", "/b/x.tar", "ms-w-1"])
        XCTAssertEqual(AppleContainer.listAll, ["list", "--all", "--format", "json"])
        XCTAssertEqual(AppleContainer.id(fromName: "ms-w-1"), "w-1")
        XCTAssertNil(AppleContainer.id(fromName: "other"))
    }

    func testJsonShapesFromTheTool() {
        let list = Data(#"[{"id":"ms-w-1","status":{"state":"running","networks":[{"ipv4Address":"192.168.65.7/24"}]}},{"configuration":{"id":"ms-w-2"},"status":{"state":"stopped"}},{"x":1}]"#.utf8)
        XCTAssertEqual(ContainerJson.parse(list), [ContainerInfo(name: "ms-w-1", state: "running", ipv4: "192.168.65.7"), ContainerInfo(name: "ms-w-2", state: "stopped", ipv4: nil)])
        let one = Data(#"{"id":"ms-w-3","status":{"state":"running","networks":[]}}"#.utf8)
        XCTAssertEqual(ContainerJson.parse(one), [ContainerInfo(name: "ms-w-3", state: "running", ipv4: nil)])
        for junk in ["", "null", "7", "[1,2]", "garbage"] { XCTAssertTrue(ContainerJson.parse(Data(junk.utf8)).isEmpty, junk) }
    }

    func testStates() {
        XCTAssertEqual(ContainerStates.workloadState("running"), .running)
        XCTAssertEqual(ContainerStates.workloadState("stopped"), .stopped)
        XCTAssertEqual(ContainerStates.workloadState("exited"), .stopped)
        XCTAssertEqual(ContainerStates.workloadState("stopping"), .deleting)
        XCTAssertEqual(ContainerStates.workloadState("something-new"), .failed)
        XCTAssertEqual(ContainerStates.workloadState(nil), .failed)
    }

    func testRecordsRoundTrip() throws {
        let record = WorkloadRecord(name: "demo", kind: "vm", cpu: 2, ramMb: 2048, diskGb: 10, gpuMode: "none", image: "ubuntu:24.04", bundleVersion: "1.0.0")
        let data = try JSONEncoder().encode(["w-1": record])
        XCTAssertEqual(try JSONDecoder().decode([String: WorkloadRecord].self, from: data)["w-1"], record)
    }
}
