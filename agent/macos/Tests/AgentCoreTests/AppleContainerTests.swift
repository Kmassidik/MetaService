import XCTest
@testable import AgentCore

final class AppleContainerTests: XCTestCase {
    private func request(_ change: ((inout [String: Any]) -> Void)? = nil) throws -> CreateWorkloadRequest {
        var body: [String: Any] = ["command_id": "c-1", "name": "demo", "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 10]
        change?(&body)
        return try CreateWorkloadRequest(body: JSONSerialization.data(withJSONObject: body))
    }

    func testTheFirstTryRunsSystemdWithTheTwoRightsItNeeds() throws {
        let args = AppleContainer.run(id: "w-abc", request: try request(), image: "docker.io/library/ubuntu:24.04")
        XCTAssertEqual(args, ["run", "--detach", "--name", "ms-w-abc", "--cpus", "2", "--memory", "2048M", "--cap-add", "NET_ADMIN", "--cap-add", "SYS_ADMIN",
                              "--label", "metaservice.id=w-abc", "docker.io/library/ubuntu:24.04", "sh", "-c", AppleContainer.systemdScript])
        XCTAssertEqual(args.count, 18, "no other flags such as more capabilities, mounts or ports")
    }

    func testThePlainTryHasNoExtraRights() throws {
        let args = AppleContainer.run(id: "w-abc", request: try request(), image: "ubuntu:24.04", mode: .plain)
        XCTAssertEqual(args, ["run", "--detach", "--name", "ms-w-abc", "--cpus", "2", "--memory", "2048M", "--label", "metaservice.id=w-abc", "ubuntu:24.04",
                              "sh", "-c", AppleContainer.plainScript])
        XCTAssertFalse(args.contains("--cap-add"))
    }

    func testBothScriptsAreFixedTextWithNothingFromTheRequest() throws {
        let other = try request { $0["name"] = "other-name"; $0["cpu"] = 4; $0["ram_mb"] = 4096 }
        for mode in [InitMode.systemd, .plain] {
            let first = AppleContainer.run(id: "w-abc", request: try request(), image: "ubuntu:24.04", mode: mode)
            let second = AppleContainer.run(id: "w-zzz", request: other, image: "docker.io/library/debian:12", mode: mode)
            XCTAssertEqual(first.last, second.last, "the script must not change with the request")
            for word in ["demo", "other-name", "w-abc", "w-zzz", "ubuntu:24.04"] { XCTAssertFalse(first.last!.contains(word), word) }
        }
    }

    func testTheSystemdScriptStaysAliveWhenSystemdCannotBeSet() {
        let script = AppleContainer.systemdScript
        XCTAssertTrue(script.contains("stay_plain()"))
        XCTAssertTrue(script.contains("exec sleep infinity"))
        XCTAssertTrue(script.contains("|| stay_plain \"systemd could not be installed\""))
        XCTAssertTrue(script.contains("[ -x /sbin/init ] || stay_plain"), "never exec an init that is not there")
        XCTAssertTrue(script.hasSuffix("echo systemd > /metaservice-init-mode\nexec /sbin/init"), "the happy path ends by handing over to systemd")
        XCTAssertTrue(script.contains("apt-get install -y -qq --no-install-recommends systemd systemd-sysv dbus libpam-systemd"))
        XCTAssertTrue(script.contains("tr -d - < /proc/sys/kernel/random/uuid > /etc/machine-id"))
        XCTAssertFalse(script.contains("set -e"), "a failing step must not end the script")
    }

    func testThePlainScriptKeepsTheVmAlive() {
        XCTAssertTrue(AppleContainer.plainScript.hasSuffix("echo plain > /metaservice-init-mode\nexec sleep infinity"))
    }

    func testBothScriptsAreValidShellText() throws {
        for script in [AppleContainer.systemdScript, AppleContainer.plainScript] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-n", "-c", script]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "sh -n rejected the script")
        }
    }

    func testReadingLogsAndTheStartProbeUseFixedArguments() {
        XCTAssertEqual(AppleContainer.logs("w-1"), ["logs", "ms-w-1"])
        XCTAssertEqual(AppleContainer.bootLogs("w-1"), ["logs", "--boot", "ms-w-1"])
        XCTAssertEqual(AppleContainer.initModeProbe("w-1"), ["exec", "ms-w-1", "cat", "/metaservice-init-mode"])
        XCTAssertEqual(AppleContainer.readySeconds, 60)
    }

    func testTheExitCodeIsReadWhereTheToolMayPutIt() {
        let list = Data(#"[{"id":"ms-a","status":{"state":"stopped","exitCode":255}},{"id":"ms-b","status":"exited","exitCode":3},{"id":"ms-c","status":"stopped"}]"#.utf8)
        XCTAssertEqual(ContainerJson.parse(list).map(\.exitCode), [255, 3, nil])
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

    func testJsonShapeWithAPlainStatusWordAndNetworksNextToIt() {
        let list = Data(#"[{"status":"running","configuration":{"id":"ms-w-4"},"networks":[{"ipv4Address":"192.168.64.9/24"}]},{"status":"stopped","configuration":{"id":"ms-w-5"},"networks":[]}]"#.utf8)
        XCTAssertEqual(ContainerJson.parse(list), [ContainerInfo(name: "ms-w-4", state: "running", ipv4: "192.168.64.9"), ContainerInfo(name: "ms-w-5", state: "stopped", ipv4: nil)])
    }

    func testStateWordsTheHelperCannotMapAreFoundOnce() {
        let infos = [ContainerInfo(name: "ms-a", state: "running", ipv4: nil), ContainerInfo(name: "ms-b", state: "paused", ipv4: nil),
                     ContainerInfo(name: "ms-c", state: "paused", ipv4: nil), ContainerInfo(name: "ms-d", state: "unknown", ipv4: nil)]
        XCTAssertEqual(ContainerStates.unmappedWords(infos), ["paused", "unknown"])
        XCTAssertEqual(ContainerStates.unmappedWarning("paused"), "container state word \"paused\" is not one the helper knows, so the VM is reported as failed")
        XCTAssertTrue(ContainerStates.unmappedWords([ContainerInfo(name: "ms-a", state: "stopped", ipv4: nil)]).isEmpty)
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
