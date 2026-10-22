import XCTest
@testable import AgentCore

/// What the helper says about itself (contract 1.3.0) and turning the chat off.
final class EngineFactsAndUninstallTests: XCTestCase {
    private let hostile = ["'; DROP TABLE x;--", "<script>alert(1)</script>", "$(reboot)", "`id`", "../../etc/passwd", "a b", String(repeating: "A", count: 70), "--privileged", "", "line\nbreak"]

    private func service(engine: Engine = SimulatedEngine(), installer: BundleInstalling? = nil) -> AgentService {
        let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, ramTotalMb: 32768, diskTotalGb: 1000, gpu: [])
        return AgentService(engine: engine, budget: SpaceBudget(ramTotalMb: 32768, diskTotalGb: 1000), specs: specs, agentVersion: "0.9.9", installer: installer)
    }

    private func body(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    // MARK: facts

    func testFactsSayWhichHelperRunsAndTheSameTextAsHealth() async throws {
        let agent = service()
        let facts = try await agent.facts()
        let health = await agent.health()
        XCTAssertEqual(facts.agentVersion, "0.9.9")
        XCTAssertEqual(facts.agentVersion, health.agentVersion)
    }

    func testAReadyEngineIsReadyAndAnEngineWithAProblemIsNot() async throws {
        let ready = try await service().facts()
        XCTAssertEqual(ready.engine, EngineInfo(identity: EngineIdentity(name: "simulated", version: nil), ready: true))
        let problem = HostProblem(code: "container_tool_missing", message: "missing", fix: "install it")
        let broken = try await service(engine: UnavailableEngine(name: "apple-container", problem: problem)).facts()
        XCTAssertEqual(broken.engine, EngineInfo(identity: EngineIdentity(name: "apple-container", version: nil), ready: false))
    }

    func testAnUnknownEngineVersionIsSentAsNullAndNeverGuessed() throws {
        let info = EngineInfo(identity: EngineIdentity(name: "apple-container", version: nil), ready: true)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(info)) as? [String: Any])
        XCTAssertTrue(json["version"] is NSNull)
    }

    func testTheAppleToolVersionIsReadFromWhatItPrintsOrIsNil() {
        XCTAssertEqual(AppleContainer.parseVersion("container CLI version 0.5.1 (build: release, commit: abc1234)\n"), "0.5.1")
        XCTAssertEqual(AppleContainer.parseVersion("1.2.3"), "1.2.3")
        for junk in ["", "no version here", "container 1.2", "v1", "\u{0}\u{0}", String(repeating: "9", count: 5000)] { XCTAssertNil(AppleContainer.parseVersion(junk), junk) }
    }

    func testTheVersionTheToolPrintsCannotCarryAnythingButDigits() throws {
        let parsed = try XCTUnwrap(AppleContainer.parseVersion("version 4.5.6'; DROP TABLE x;-- $(reboot)"))
        XCTAssertEqual(parsed, "4.5.6")
    }

    // MARK: the uninstall request

    func testAGoodUninstallRequestIsRead() throws {
        XCTAssertNil(try BundleUninstallRequest(body: body(["command_id": "c-1"])).workloadId)
        XCTAssertEqual(try BundleUninstallRequest(body: body(["command_id": "c-1", "workload_id": "w-1"])).workloadId, "w-1")
    }

    func testEveryBadUninstallFieldIsRefused() {
        for text in hostile {
            XCTAssertThrowsError(try BundleUninstallRequest(body: body(["command_id": text])), "command_id \(text.prefix(20))")
            XCTAssertThrowsError(try BundleUninstallRequest(body: body(["command_id": "c-1", "workload_id": text])), "workload_id \(text.prefix(20))")
        }
        let bad: [[String: Any]] = [[:], ["command_id": 5], ["command_id": "c", "surprise": 1], ["command_id": "c", "path": "/bin/sh"], ["command_id": "c", "version": "1.2.3"]]
        for item in bad { XCTAssertThrowsError(try BundleUninstallRequest(body: body(item)), "\(item)") }
        for raw in ["", "{", "null", "[]", "\"text\""] { XCTAssertThrowsError(try BundleUninstallRequest(body: Data(raw.utf8)), raw) }
    }

    func testTheUninstallScriptKeepsTheConversations() {
        let script = AppleContainer.bundleUninstallScript
        XCTAssertTrue(script.contains("systemctl disable --now metaservice-chat"))
        XCTAssertFalse(script.contains("chat-data"), "the folder with the conversations is not touched")
        XCTAssertFalse(script.contains("rm -rf"), "nothing is deleted recursively")
        XCTAssertFalse(script.contains("chat.key"))
    }

    // MARK: the service

    func testUninstallRunsOnTheInstallerAndFinishes() async throws {
        let installer = RecordingInstaller()
        let agent = service(installer: installer)
        let started = try await agent.uninstallBundle(try BundleUninstallRequest(body: body(["command_id": "u-1"])))
        XCTAssertEqual(started.type, .bundleUninstall)
        let done = try await finished(agent, "u-1")
        XCTAssertEqual(done.state, .succeeded)
        XCTAssertEqual(installer.uninstalled, [nil])
    }

    func testARepeatedUninstallCommandRunsOnce() async throws {
        let installer = RecordingInstaller()
        let agent = service(installer: installer)
        let request = try BundleUninstallRequest(body: body(["command_id": "u-2"]))
        _ = try await agent.uninstallBundle(request)
        _ = try await finished(agent, "u-2")
        _ = try await agent.uninstallBundle(request)
        XCTAssertEqual(installer.uninstalled.count, 1)
    }

    func testUninstallInAWorkloadThatIsNotThereIsNotFound() async throws {
        let agent = service(installer: RecordingInstaller())
        do {
            _ = try await agent.uninstallBundle(try BundleUninstallRequest(body: body(["command_id": "u-3", "workload_id": "w-none"])))
            XCTFail("a missing workload must be refused")
        } catch AgentError.notFound {}
    }

    func testAFailingUninstallIsReportedAsFailedWithoutDetails() async throws {
        let installer = RecordingInstaller()
        installer.failure = EngineError.failed("secret path /Users/x leaked")
        let agent = service(installer: installer)
        _ = try await agent.uninstallBundle(try BundleUninstallRequest(body: body(["command_id": "u-4"])))
        let done = try await finished(agent, "u-4", wanting: .failed)
        XCTAssertEqual(done.result?["error"], "the chat could not be turned off")
        XCTAssertFalse(String(describing: done.result).contains("/Users"))
    }

    func testTheSimulatedEngineCanClearAWorkloadsBundleVersion() async throws {
        let engine = SimulatedEngine()
        let request = try CreateWorkloadRequest(body: body(["command_id": "c", "name": "demo", "kind": "vm", "cpu": 1, "ram_mb": 512, "disk_gb": 1]))
        _ = try await engine.create(id: "w-1", request: request)
        try await engine.setBundleVersion(id: "w-1", version: "1.2.3")
        var listed = try await engine.list()
        XCTAssertEqual(listed.first?.bundleVersion, "1.2.3")
        try await engine.setBundleVersion(id: "w-1", version: nil)
        listed = try await engine.list()
        XCTAssertNil(listed.first?.bundleVersion)
    }

    // MARK: a create that fails says why

    private func createRequest(_ id: String) throws -> CreateWorkloadRequest {
        try CreateWorkloadRequest(body: body(["command_id": id, "name": "demo", "kind": "vm", "cpu": 1, "ram_mb": 1024, "disk_gb": 5]))
    }

    func testAVmThatDidNotStartPassesItsReasonOnInTheFailedCommand() async throws {
        let engine = SimulatedEngine()
        await engine.failCreates(EngineError.notReady("The VM did not start.\nTry 1, with systemd: it stopped right after it started (exit code 255)."))
        let agent = service(engine: engine)
        _ = try await agent.create(try createRequest("c-why"))
        let command = try await finished(agent, "c-why", wanting: .failed)
        XCTAssertEqual(command.result?["error"], "The VM did not start.\nTry 1, with systemd: it stopped right after it started (exit code 255).")
    }

    func testAnyOtherCreateFailureStaysTheFixedSentence() async throws {
        let engine = SimulatedEngine()
        await engine.failCreates(EngineError.failed("container run exited with 1: secret detail"))
        let agent = service(engine: engine)
        _ = try await agent.create(try createRequest("c-plain"))
        let command = try await finished(agent, "c-plain", wanting: .failed)
        XCTAssertEqual(command.result?["error"], "the machine could not create the workload")
    }

    func testAWorkloadWithAReasonAndAModeCarriesThemInItsJson() throws {
        let reason = StoppedReason(exitCode: 255, logTail: "line")
        var workload = Workload(id: "w-1", name: "x", kind: .vm, state: .stopped, cpu: 1, ramMb: 1024, diskGb: 5, gpuMode: .none, stoppedReason: reason, initMode: .plain)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let parsed = try JSONSerialization.jsonObject(with: encoder.encode(workload)) as? [String: Any]
        XCTAssertEqual(parsed?["stopped_reason"] as? [String: AnyHashable], ["exit_code": 255, "log_tail": "line"])
        XCTAssertEqual(parsed?["init_mode"] as? String, "plain")
        workload.stoppedReason = nil
        workload.initMode = nil
        let bare = String(decoding: try encoder.encode(workload), as: UTF8.self)
        XCTAssertFalse(bare.contains("stopped_reason") || bare.contains("init_mode"), "both fields are left out when empty: \(bare)")
    }

    private func finished(_ agent: AgentService, _ id: String, wanting: CommandState = .succeeded) async throws -> Command {
        for _ in 0..<200 {
            let command = try await agent.command(id)
            if command.state == wanting { return command }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw EngineError.failed("the command did not finish")
    }
}

private final class RecordingInstaller: BundleInstalling, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String?] = []
    var failure: Error?

    var uninstalled: [String?] { lock.withLock { calls } }

    func install(_ request: BundleInstallRequest) async throws -> [String: String] { [:] }

    func uninstall(workloadId: String?) async throws {
        if let failure { throw failure }
        lock.withLock { calls.append(workloadId) }
    }

    func installedVersion() async -> String? { nil }
}
