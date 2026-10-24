import XCTest
@testable import AgentCore

final class ConsoleTests: XCTestCase {
    private func makeEngine(running: Bool = true) async throws -> SimulatedEngine {
        let engine = SimulatedEngine()
        let request = try CreateWorkloadRequest(body: JSONSerialization.data(withJSONObject:
            ["command_id": "c-1", "name": "demo", "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 10] as [String: Any]))
        _ = try await engine.create(id: "w-1", request: request)
        if !running { try await engine.setRunning(id: "w-1", running: false) }
        return engine
    }

    private func alive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    // MARK: the command list

    func testAppleCommandIsOneFixedListWithoutAShell() throws {
        XCTAssertEqual(try AppleContainer.attach("w-1"), ["exec", "-it", "ms-w-1", "/bin/sh", "-l"])
    }

    func testHostileIdsNeverReachTheCommand() {
        let hostile = ["w-1; reboot", "$(id)", "`id`", "a b", "../x", "-it", "--privileged", "W-1", "", "w\n1", String(repeating: "a", count: 64)]
        for id in hostile {
            XCTAssertThrowsError(try AppleContainer.attach(id), id) { XCTAssertEqual($0 as? EngineError, .notFound) }
        }
    }

    func testAnAddressGivesARootPromptThatNamesIt() throws {
        XCTAssertEqual(
            try AppleContainer.attach("w-1", address: "10.0.0.5"),
            ["exec", "-it", "-e", "PS1=root@10.0.0.5:\\w# ", "ms-w-1", "/bin/sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash --noprofile --norc -i; exec sh -i"]
        )
    }

    func testAMissingOrOddAddressKeepsTheLoginShell() throws {
        let login = ["exec", "-it", "ms-w-1", "/bin/sh", "-l"]
        XCTAssertEqual(try AppleContainer.attach("w-1", address: nil), login)
        let hostile = ["", "1.2.3", "1.2.3.4; reboot", "$(id)", "a b", "--help", "01.2.3.4", "256.1.1.1", "1.2.3.4\n", "10.0.0.5.6"]
        for address in hostile {
            XCTAssertEqual(try AppleContainer.attach("w-1", address: address), login, address)
        }
    }

    func testCheckedAddressIsCanonicalDottedTextOrNil() {
        XCTAssertEqual(AppleContainer.checkedAddress("10.0.0.5"), "10.0.0.5")
        XCTAssertEqual(AppleContainer.checkedAddress("0.0.0.0"), "0.0.0.0")
        XCTAssertEqual(AppleContainer.checkedAddress("255.255.255.255"), "255.255.255.255")
        for odd in [nil, "", "10.0.0", "10.0.0.5.6", "010.0.0.5", "256.0.0.1", "-1.0.0.1", "10.0.0.5 ", "10.0.0.5;id", "a.b.c.d"] {
            XCTAssertNil(AppleContainer.checkedAddress(odd), String(describing: odd))
        }
    }

    func testSimulatedAndUnavailableEngines() async throws {
        let engine = try await makeEngine()
        let command = try await engine.attach(id: "w-1")
        XCTAssertEqual(command, ["/bin/sh"])
        do { _ = try await engine.attach(id: "w-2"); XCTFail("unknown workload") } catch { XCTAssertEqual(error as? EngineError, .notFound) }
        let none = UnavailableEngine(name: "x", problem: HostProblem(code: "c", message: "m", fix: "f"))
        do { _ = try await none.attach(id: "w-1"); XCTFail("unavailable") } catch { XCTAssertEqual(error as? EngineError, .notFound) }
    }

    // MARK: one console per workload

    func testOneConsolePerWorkload() {
        let registry = ConsoleRegistry()
        XCTAssertTrue(registry.claim("w-1"))
        XCTAssertFalse(registry.claim("w-1"), "a second console is refused")
        XCTAssertTrue(registry.isOpen("w-1"))
        XCTAssertTrue(registry.claim("w-2"), "another workload is independent")
        registry.release("w-1")
        XCTAssertFalse(registry.isOpen("w-1"))
        XCTAssertTrue(registry.claim("w-1"), "free again after release")
    }

    // MARK: a real pty

    func testTypeAndReadThroughARealPty() async throws {
        let pty = try PtyProcess(command: try await makeEngine().attach(id: "w-1"))
        defer { pty.stop() }
        pty.write(Array("echo console-$((6*7))\n".utf8))
        var seen = ""
        for await chunk in pty.output {
            seen += String(decoding: chunk, as: UTF8.self)
            if seen.contains("console-42") { break }
        }
        XCTAssertTrue(seen.contains("console-42"))
    }

    func testResizeReachesTheTerminal() async throws {
        let pty = try PtyProcess(command: ["/bin/sh"])
        defer { pty.stop() }
        pty.resize(TerminalSize(cols: 132, rows: 43))
        pty.write(Array("stty size\n".utf8))
        var seen = ""
        for await chunk in pty.output {
            seen += String(decoding: chunk, as: UTF8.self)
            if seen.contains("43 132") { break }
        }
        XCTAssertTrue(seen.contains("43 132"))
    }

    func testStopKillsTheChildAndEndsTheOutput() async throws {
        let pty = try PtyProcess(command: ["/bin/sh"])
        let pid = pty.processIdentifier
        XCTAssertTrue(alive(pid))
        pty.stop()
        let gone = await waitUntil { !alive(pid) }
        XCTAssertTrue(gone, "the shell process is gone after stop")
        for await _ in pty.output {}
    }

    func testAShellThatIgnoresHangupIsStillKilled() async throws {
        let pty = try PtyProcess(command: ["/bin/sh", "-c", "trap '' HUP TERM; while :; do sleep 1; done"])
        let pid = pty.processIdentifier
        pty.stop()
        let gone = await waitUntil { !alive(pid) }
        XCTAssertTrue(gone, "a program that shrugs off the hangup is killed anyway")
    }

    func testOutputEndsWhenTheShellExits() async throws {
        let pty = try PtyProcess(command: ["/bin/sh", "-c", "echo bye"])
        var seen = ""
        for await chunk in pty.output { seen += String(decoding: chunk, as: UTF8.self) }
        XCTAssertTrue(seen.contains("bye"))
    }

    func testNoProgramAndMissingProgramFail() {
        XCTAssertThrowsError(try PtyProcess(command: [])) { XCTAssertEqual($0 as? PtyError, .noProgram) }
        XCTAssertThrowsError(try PtyProcess(command: ["/no/such/program"])) { XCTAssertEqual($0 as? PtyError, .notStarted) }
    }

    // MARK: a full frame, and the workload going away

    func testAFullFrameOfExactlyTheLimitIsTakenWithoutStallingTheShell() async throws {
        let pty = try PtyProcess(command: ["/bin/sh"])
        defer { pty.stop() }
        pty.write(Array(String(repeating: ":\n", count: TerminalFrames.maxInputBytes / 2).utf8))
        pty.write(Array("echo still=$((1+1))\n".utf8))
        var tail = [UInt8]()
        let marker = Array("still=2".utf8)
        var found = false
        for await chunk in pty.output {
            tail = Array((tail + chunk).suffix(chunk.count + marker.count))
            found = tail.indices.contains { tail[$0...].starts(with: marker) }
            if found { break }
        }
        XCTAssertTrue(found, "the echo of 64 KiB must not block the shell")
    }

    private func service(_ engine: SimulatedEngine) -> AgentService {
        let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, ramTotalMb: 32768, diskTotalGb: 1000, gpu: [])
        return AgentService(engine: engine, budget: SpaceBudget(ramTotalMb: 32768, diskTotalGb: 1000), specs: specs, agentVersion: "0.9.9")
    }

    func testStoppingTheWorkloadEndsItsConsole() async throws {
        let engine = try await makeEngine()
        let service = service(engine)
        let ended = Ended()
        XCTAssertTrue(service.consoles.claim("w-1") { ended.set($0) })
        XCTAssertTrue(service.consoles.claim("w-2") { _ in XCTFail("another workload's console") })
        _ = try await service.stop(commandId: "c-stop", id: "w-1")
        XCTAssertEqual(ended.value, .vmStopped)
        XCTAssertEqual(ConsoleClose.vmStopped.code, 1000)
    }

    func testDeletingTheWorkloadEndsItsConsole() async throws {
        let engine = try await makeEngine()
        let service = service(engine)
        let ended = Ended()
        XCTAssertTrue(service.consoles.claim("w-1") { ended.set($0) })
        _ = try await service.delete(commandId: "c-del", id: "w-1")
        XCTAssertEqual(ended.value, .vmDeleted)
    }
}

private final class Ended: @unchecked Sendable {
    private let lock = NSLock()
    private var close: ConsoleClose?
    var value: ConsoleClose? { lock.withLock { close } }
    func set(_ new: ConsoleClose) { lock.withLock { close = new } }
}
