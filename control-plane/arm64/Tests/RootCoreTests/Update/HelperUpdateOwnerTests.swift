import XCTest
@testable import RootCore

/// Runs the real update script with /bin/sh against a throwaway box, with fake `systemctl`, `launchctl`, `uname` and `curl` first in PATH.
/// The fakes log every call and start a stand-in helper (`sleep`), so the tests can count the helpers and see who started them.
final class HelperUpdateOwnerTests: XCTestCase {
    private var root = URL(fileURLWithPath: "/")
    private var box: URL { root.appendingPathComponent("box") }
    private var fakes: URL { root.appendingPathComponent("fakes") }
    private let fakeSeconds = 120

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ms-owner-\(UUID().uuidString)")
        for folder in [box.appendingPathComponent("bin"), box.appendingPathComponent("state"), box.appendingPathComponent("logs"), fakes] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try write(box, "manifest.json", #"{"made_by":"metaservice"}"#)
        try write(box, "bin/metaservice-agent", program("OLD"), executable: true)
        try write(box, "stop.sh", PlanScripts.stopScript(), executable: true)
        try write(box, "start.sh", "#!/bin/sh\ncd \"$(dirname \"$0\")\" || exit 1\necho start.sh >> calls.log\n\(spawn)\n", executable: true)
        try write(fakes, "uname", "#!/bin/sh\necho \"$FAKE_OS\"\n", executable: true)
        try write(fakes, "curl", "#!/bin/sh\ngrep -q BROKEN bin/metaservice-agent && echo 000 || echo 200\n", executable: true)
        try write(fakes, "systemctl", """
        #!/bin/sh
        shift
        echo "systemctl $*" >> calls.log
        case "$1" in
          stop) [ ! -f state/agent.pid ] || kill "$(cat state/agent.pid)" 2>/dev/null; rm -f state/agent.pid ;;
          restart) [ ! -f state/agent.pid ] || kill "$(cat state/agent.pid)" 2>/dev/null; \(spawn) ;;
        esac
        """, executable: true)
        try write(fakes, "launchctl", """
        #!/bin/sh
        echo "launchctl $*" >> calls.log
        case "$1" in
          print) [ "$FAKE_LAUNCHD" = 1 ] && [ ! -f launchd.unloaded ] ;;
          bootout) touch launchd.unloaded; [ ! -f state/agent.pid ] || kill "$(cat state/agent.pid)" 2>/dev/null ;;
          bootstrap|load) rm -f launchd.unloaded; \(spawn) ;;
          kickstart) [ ! -f state/agent.pid ] || kill "$(cat state/agent.pid)" 2>/dev/null; \(spawn) ;;
        esac
        """, executable: true)
        try runShell("cd '\(box.path)'; \(spawn)", environment: [:], input: nil)
    }

    override func tearDownWithError() throws {
        let spawned = (try? String(contentsOf: box.appendingPathComponent("spawned"), encoding: .utf8)) ?? ""
        spawned.split(separator: "\n").forEach { _ = try? runShell("kill \($0) 2>/dev/null; true", environment: [:], input: nil) }
        try? FileManager.default.removeItem(at: root)
    }

    /// A stand-in helper: detached from the script's output so the run can finish, its pid in the pid file and in `spawned`.
    private var spawn: String { "sleep \(fakeSeconds) >/dev/null 2>&1 </dev/null & echo $! > state/agent.pid; echo $! >> spawned" }

    private func program(_ tag: String) -> String {
        "#!/bin/sh\n# \(tag)\n[ \"$1\" != autostart ] || { [ ! -f .effective ] || echo '{\"effective\":true}'; }\n"
    }

    private func write(_ folder: URL, _ name: String, _ text: String, executable: Bool = false) throws {
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }

    @discardableResult
    private func runShell(_ script: String, environment: [String: String], input: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = environment.merging(["PATH": "\(fakes.path):/usr/bin:/bin", "HOME": root.path]) { mine, _ in mine }
        let out = Pipe(), inPipe = Pipe()
        process.standardOutput = out
        process.standardInput = inPipe
        try process.run()
        inPipe.fileHandleForWriting.write(Data((input ?? "").utf8))
        try inPipe.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func checksum(_ text: String) throws -> String {
        let file = root.appendingPathComponent("sum-input")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return try runShell("shasum -a 256 '\(file.path)' | cut -d' ' -f1", environment: [:], input: nil).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func update(newText: String, os: String, launchd: Bool = false, plist: Bool = true) throws -> String {
        let agents = root.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        if launchd && plist { try "<plist/>".write(to: agents.appendingPathComponent("io.metaservice.agent.plist"), atomically: true, encoding: .utf8) }
        let script = try HelperUpdateScript.make(box: box.path, agentPort: 9, expectedBuild: try checksum(newText))
        let output = try runShell(script, environment: ["FAKE_OS": os, "FAKE_LAUNCHD": launchd ? "1" : "0"], input: newText)
        return HelperUpdateScript.code(in: output)
    }

    private func calls() -> [String] {
        ((try? String(contentsOf: box.appendingPathComponent("calls.log"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    private func liveHelpers() throws -> Int {
        let spawned = (try? String(contentsOf: box.appendingPathComponent("spawned"), encoding: .utf8)) ?? ""
        return try spawned.split(separator: "\n").filter { try runShell("kill -0 \($0) 2>/dev/null && echo y", environment: [:], input: nil).contains("y") }.count
    }

    private func installedProgram() throws -> String { try String(contentsOf: box.appendingPathComponent("bin/metaservice-agent"), encoding: .utf8) }

    func testWithAutostartInForceTheUnitOwnsTheNewHelperAndNothingElseStartsIt() throws {
        try write(box, ".effective", "")
        XCTAssertEqual(try update(newText: program("NEW"), os: "Linux"), "updated")
        XCTAssertTrue(calls().contains("systemctl restart metaservice-agent.service"), "\(calls())")
        XCTAssertFalse(calls().contains("start.sh"), "start.sh must not start a second owner: \(calls())")
        XCTAssertEqual(try liveHelpers(), 1)
        XCTAssertTrue(try installedProgram().contains("NEW"))
    }

    func testWithoutAutostartTheOldStartScriptStillStartsTheHelper() throws {
        XCTAssertEqual(try update(newText: program("NEW"), os: "Linux"), "updated")
        XCTAssertTrue(calls().contains("start.sh"), "\(calls())")
        XCTAssertFalse(calls().contains { $0.hasPrefix("systemctl restart") }, "\(calls())")
        XCTAssertEqual(try liveHelpers(), 1)
    }

    func testARolledBackBuildIsRestartedByTheSameOwnerAndOnlyOneHelperRuns() throws {
        try write(box, ".effective", "")
        XCTAssertEqual(try update(newText: program("BROKEN"), os: "Linux"), "rolled_back")
        XCTAssertEqual(calls().filter { $0 == "systemctl restart metaservice-agent.service" }.count, 2, "\(calls())")
        XCTAssertFalse(calls().contains("start.sh"), "\(calls())")
        XCTAssertTrue(try installedProgram().contains("OLD"))
        XCTAssertEqual(try liveHelpers(), 1)
    }

    func testARolledBackBuildWithoutAutostartIsRestartedByTheStartScript() throws {
        XCTAssertEqual(try update(newText: program("BROKEN"), os: "Linux"), "rolled_back")
        XCTAssertEqual(calls().filter { $0 == "start.sh" }.count, 2, "\(calls())")
        XCTAssertEqual(try liveHelpers(), 1)
    }

    func testOnAMacWithItsLaunchAgentLoadedLaunchdRestartsTheHelper() throws {
        XCTAssertEqual(try update(newText: program("NEW"), os: "Darwin", launchd: true), "updated")
        XCTAssertTrue(calls().contains { $0.hasPrefix("launchctl bootout gui/") && $0.hasSuffix("/io.metaservice.agent") }, "\(calls())")
        XCTAssertTrue(calls().contains { $0.hasPrefix("launchctl bootstrap gui/") && $0.hasSuffix("/Library/LaunchAgents/io.metaservice.agent.plist") }, "\(calls())")
        XCTAssertFalse(calls().contains { $0.hasPrefix("launchctl kickstart") }, "never kickstart a replaced Mac build: \(calls())")
        XCTAssertFalse(calls().contains("start.sh"), "\(calls())")
        XCTAssertEqual(try liveHelpers(), 1)
    }

    func testARolledBackMacBuildIsLoadedAgainThroughLaunchdToo() throws {
        XCTAssertEqual(try update(newText: program("BROKEN"), os: "Darwin", launchd: true), "rolled_back")
        XCTAssertEqual(calls().filter { $0.hasPrefix("launchctl bootstrap gui/") }.count, 2, "\(calls())")
        XCTAssertFalse(calls().contains { $0.hasPrefix("launchctl kickstart") }, "\(calls())")
        XCTAssertTrue(try installedProgram().contains("OLD"))
        XCTAssertEqual(try liveHelpers(), 1)
    }

    func testAMacWhoseLaunchAgentFileIsMissingFallsBackToKickstart() throws {
        XCTAssertEqual(try update(newText: program("NEW"), os: "Darwin", launchd: true, plist: false), "updated")
        XCTAssertTrue(calls().contains { $0.hasPrefix("launchctl kickstart -k gui/") }, "\(calls())")
        XCTAssertFalse(calls().contains { $0.hasPrefix("launchctl bootstrap") }, "\(calls())")
    }

    func testOnAMacWithoutTheLaunchAgentTheStartScriptStays() throws {
        XCTAssertEqual(try update(newText: program("NEW"), os: "Darwin", launchd: false), "updated")
        XCTAssertTrue(calls().contains("start.sh"), "\(calls())")
        XCTAssertFalse(calls().contains { $0.hasPrefix("launchctl kickstart") }, "\(calls())")
    }
}
