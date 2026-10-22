import XCTest
import MSCore
@testable import AgentCore

final class SshKeyLinesTests: XCTestCase {
    private let blob = "AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE01"

    func testEveryAllowedKeyTypeIsAccepted() {
        for type in ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "ssh-rsa", "sk-ssh-ed25519@openssh.com"] {
            XCTAssertTrue(SshKeyLines.isValid("\(type) \(blob) alice@laptop"), type)
            XCTAssertTrue(SshKeyLines.isValid("\(type) \(blob)"), "\(type) without a comment")
        }
        XCTAssertTrue(SshKeyLines.isValid("ssh-rsa \(blob)== a.b_c-d+e:f@g"), "padding and the full comment alphabet")
    }

    func testEveryKindOfBadLineIsRefused() {
        let bad = [
            "ssh-ed25519 \(blob) a\nssh-ed25519 \(blob) b", "ssh-ed25519 \(blob) a\r", "ssh-ed25519 \(blob) a\n", "ssh-ed25519 \(blob) a\0b",
            "command=\"/bin/sh\" ssh-ed25519 \(blob)", "no-pty ssh-ed25519 \(blob)", "ssh-dss \(blob)", "ssh-ed25519\(blob)", "ssh-ed25519  \(blob)",
            "ssh-ed25519 \(blob) \"quoted\"", "ssh-ed25519 \(blob) a;b", "ssh-ed25519 \(blob) a b", "ssh-ed25519 \(blob) $(id)", "ssh-ed25519 ", "ssh-ed25519",
            "", " ssh-ed25519 \(blob)", "ssh-ed25519 \(blob) " + String(repeating: "a", count: 65), "ssh-ed25519 \(blob)====", "ssh-ed25519 not*base64",
        ]
        for line in bad { XCTAssertFalse(SshKeyLines.isValid(line), line.debugDescription) }
    }

    func testALineOverTheLimitIsRefused() {
        let limit = SshKeyLines.maxLineLength
        let fits = "ssh-ed25519 " + String(repeating: "A", count: limit - "ssh-ed25519 ".count)
        XCTAssertEqual(fits.utf8.count, limit)
        XCTAssertTrue(SshKeyLines.isValid(fits))
        XCTAssertFalse(SshKeyLines.isValid(fits + "A"))
    }

    func testMoreThanTwentyKeysAreRefusedAndTwentyAreNot() throws {
        let key = "ssh-ed25519 \(blob)"
        XCTAssertNoThrow(try SshKeyLines.validate(Array(repeating: key, count: SshKeyLines.maxKeys)))
        XCTAssertThrowsError(try SshKeyLines.validate(Array(repeating: key, count: SshKeyLines.maxKeys + 1)))
        XCTAssertNoThrow(try SshKeyLines.validate([]))
    }

    func testTheRefusalNamesThePositionAndNeverTheKey() {
        let secret = "ssh-ed25519 \(blob) \"oops\""
        XCTAssertThrowsError(try SshKeyLines.validate(["ssh-ed25519 \(blob)", secret])) { error in
            let message = (error as? InputError)?.message ?? ""
            XCTAssertTrue(message.contains("keys/1"), message)
            XCTAssertFalse(message.contains(blob), message)
        }
    }

    func testTheRequestBodyIsReadStrictly() throws {
        func body(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
        let key = "ssh-ed25519 \(blob) a"
        XCTAssertEqual(try SshKeysRequest(body: body(["keys": [key]])).keys, [key])
        XCTAssertEqual(try SshKeysRequest(body: body(["keys": []])).keys, [])
        XCTAssertThrowsError(try SshKeysRequest(body: body([:])), "keys is required")
        XCTAssertThrowsError(try SshKeysRequest(body: body(["keys": [key], "extra": 1])))
        XCTAssertThrowsError(try SshKeysRequest(body: body(["keys": "ssh-ed25519"])))
        XCTAssertThrowsError(try SshKeysRequest(body: body(["keys": [5]])))
        XCTAssertThrowsError(try SshKeysRequest(body: body(["keys": [key + "\nssh-rsa AAAA"]])))
        XCTAssertThrowsError(try SshKeysRequest(body: Data("not json".utf8)))
    }

    func testTheFileContentHasOneKeyPerLineAndAClosingNewline() {
        XCTAssertEqual(String(decoding: SshKeyLines.fileContent(["a", "b"]), as: UTF8.self), "a\nb\n")
        XCTAssertTrue(SshKeyLines.fileContent([]).isEmpty, "an empty list leaves an empty managed file")
    }
}

final class SshKeysScriptTests: XCTestCase {
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE01 alice@laptop"

    func testTheArgumentsAreAFixedExecOfTheFixedScriptWithoutAnyKey() {
        let args = SshKeysScript.arguments(id: "w-abc")
        XCTAssertEqual(args, ["exec", "-i", "ms-w-abc", "/bin/sh", "-c", SshKeysScript.text])
        XCTAssertEqual(SshKeysScript.arguments(id: "w-zzz").last, args.last, "the script text does not change with the VM")
    }

    func testTheScriptWritesAtomicallyWithTheRightModes() {
        let script = SshKeysScript.text
        for line in ["mkdir -p /root/.ssh", "chmod 700 /root/.ssh", "cat > /root/.ssh/authorized_keys.new", "chmod 600 /root/.ssh/authorized_keys.new",
                     "mv -f /root/.ssh/authorized_keys.new /root/.ssh/authorized_keys"] {
            XCTAssertTrue(script.contains(line), line)
        }
        let order = ["cat > /root/.ssh/authorized_keys.new", "chmod 600", "mv -f"].compactMap { script.range(of: $0)?.lowerBound }
        XCTAssertEqual(order, order.sorted(), "write, then set the mode, then swap in")
        XCTAssertFalse(script.contains("apt-get") || script.contains("systemctl"), "sshd is only reported, never installed or started")
    }

    func testTheScriptIsValidShellText() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", "-c", SshKeysScript.text]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testTheReportLineIsReadAndNothingElseIsGuessed() {
        XCTAssertEqual(SshKeysScript.parseState("sshd=running\n"), .running)
        XCTAssertEqual(SshKeysScript.parseState("noise\nsshd=installed\n"), .installed)
        XCTAssertEqual(SshKeysScript.parseState("sshd=missing"), .missing)
        XCTAssertNil(SshKeysScript.parseState(""))
        XCTAssertNil(SshKeysScript.parseState("sshd=maybe\n"))
    }

    func testApplySendsTheKeysOnStandardInputOnly() async throws {
        let seen = Recorded()
        let result = try await SshKeysScript.apply(id: "w-1", keys: [key]) { arguments, input in
            seen.set(arguments, input)
            return "sshd=installed\n"
        }
        XCTAssertEqual(result, SshKeysResult(applied: 1, sshd: .installed))
        XCTAssertEqual(seen.input, Data((key + "\n").utf8))
        XCTAssertFalse(seen.arguments.contains { $0.contains("AAAAC3") || $0.contains("alice") }, "no key text in argv")
    }

    func testApplyFailsWhenTheVmDoesNotReport() async {
        do {
            _ = try await SshKeysScript.apply(id: "w-1", keys: []) { _, _ in "" }
            XCTFail("no report must fail")
        } catch { XCTAssertEqual(error as? EngineError, .failed("the VM did not report whether sshd is there")) }
    }

    func testApplyPassesTheToolsFailureOn() async {
        do {
            _ = try await SshKeysScript.apply(id: "w-1", keys: [key]) { _, _ in throw EngineError.failed("container exec exited with 1") }
            XCTFail("a failed exec must fail")
        } catch { XCTAssertEqual(error as? EngineError, .failed("container exec exited with 1")) }
    }

    /// What one fake run was given.
    private final class Recorded: @unchecked Sendable {
        private(set) var arguments: [String] = []
        private(set) var input = Data()
        func set(_ arguments: [String], _ input: Data) { self.arguments = arguments; self.input = input }
    }
}

final class SshKeysServiceTests: XCTestCase {
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE01 alice@laptop"
    private let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, ramTotalMb: 32768, diskTotalGb: 500, gpu: [])

    private func machine(running: Bool = true) async throws -> (AgentService, SimulatedEngine, String) {
        let engine = SimulatedEngine()
        let request = try CreateWorkloadRequest(body: JSONSerialization.data(withJSONObject: ["command_id": "c-1", "name": "demo", "kind": "vm", "cpu": 1, "ram_mb": 1024, "disk_gb": 5]))
        let made = try await engine.create(id: "w-1", request: request)
        if !running { try await engine.setRunning(id: made.id, running: false) }
        let service = AgentService(engine: engine, budget: SpaceBudget(ramTotalMb: 32768, diskTotalGb: 1000), specs: specs, agentVersion: "0.9.9")
        return (service, engine, made.id)
    }

    func testARunningVmGetsTheWholeListAndReportsSshd() async throws {
        let (service, engine, id) = try await machine()
        await engine.setSshd(.running)
        let result = try await service.applySshKeys(id: id, keys: [key, key.replacingOccurrences(of: "alice", with: "bob")])
        XCTAssertEqual(result, SshKeysResult(applied: 2, sshd: .running))
        let stored = await engine.sshKeys[id]
        XCTAssertEqual(stored?.count, 2)
        let replaced = try await service.applySshKeys(id: id, keys: [])
        XCTAssertEqual(replaced.applied, 0)
        let afterwards = await engine.sshKeys[id]
        XCTAssertEqual(afterwards, [], "the list is replaced, not added to")
    }

    func testTheResultEncodesLikeTheContract() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SshKeysResult(applied: 3, sshd: .missing))) as? [String: Any]
        XCTAssertEqual(json?["applied"] as? Int, 3)
        XCTAssertEqual(json?["sshd"] as? String, "missing")
    }

    func testTheKeysAreNeverInTheRecordedCommandLine() async throws {
        let (service, engine, id) = try await machine()
        _ = try await service.applySshKeys(id: id, keys: [key])
        let runs = await engine.sshRuns
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.arguments, SshKeysScript.arguments(id: id), "the atomic-write script constant is what runs")
        XCTAssertEqual(runs.first?.input, Data((key + "\n").utf8))
        XCTAssertFalse(runs.first?.arguments.joined(separator: " ").contains("alice@laptop") ?? true)
    }

    func testAnUnknownVmIsNotFound() async throws {
        let (service, _, _) = try await machine()
        do { _ = try await service.applySshKeys(id: "w-nope", keys: []); XCTFail("unknown") } catch { XCTAssertEqual(error as? EngineError, .notFound) }
    }

    func testAStoppedVmIsNotRunning() async throws {
        let (service, engine, id) = try await machine(running: false)
        do { _ = try await service.applySshKeys(id: id, keys: [key]); XCTFail("stopped") } catch { XCTAssertEqual(error as? EngineError, .notRunning) }
        let runs = await engine.sshRuns
        XCTAssertTrue(runs.isEmpty)
    }

    func testABadKeyIsRefusedBeforeAnythingRuns() async throws {
        let (service, engine, id) = try await machine()
        do { _ = try await service.applySshKeys(id: id, keys: ["command=\"x\" " + key]); XCTFail("options") } catch { XCTAssertTrue(error is InputError) }
        let runs = await engine.sshRuns
        XCTAssertTrue(runs.isEmpty)
    }

    func testTheUnavailableEngineHasNoVms() async {
        let engine = UnavailableEngine(name: "apple-container", problem: HostProblem(code: "x", message: "m", fix: "f"))
        do { _ = try await engine.applySshKeys(id: "w-1", keys: []); XCTFail("unavailable") } catch { XCTAssertEqual(error as? EngineError, .notFound) }
    }
}
