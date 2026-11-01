import XCTest
@testable import AgentCore

private let startScript = """
#!/bin/sh
cd "$(dirname "$0")" || exit 1
nohup ./bin/metaservice-agent run --state-dir state --engine apple --port 9101 --bind 127.0.0.1 --chat-port 9200 --chat-bind 127.0.0.1 --heartbeat-seconds 5 >> logs/agent.log 2>&1 &
echo $! > state/agent.pid

"""

private final class FakeFiles: AutostartFiles, @unchecked Sendable {
    var data: [String: Data] = [:]
    var alive: Set<Int32> = []

    func read(_ path: String) -> Data? { data[path] }
    func write(_ contents: Data, to path: String) throws { data[path] = contents }
    func remove(_ path: String) throws { data[path] = nil }
    func processAlive(_ pid: Int32) -> Bool { alive.contains(pid) }
}

/// A launchctl and defaults that remember what they were asked, and answer from a few switches.
private final class FakeMac: @unchecked Sendable {
    var calls: [String] = []
    var loaded = false
    var autoLogin: String? = "kurnia"
    var bootstrapFails = false
    var loginWindowUnreadable = false

    var run: BaselineChecks.Run {
        { [self] executable, arguments in
            let call = ([executable] + arguments).joined(separator: " ")
            calls.append(call)
            switch (executable, arguments.first) {
            case ("/bin/launchctl", "print"):
                guard loaded else { throw CocoaError(.fileNoSuchFile) }
                return Data("state = running".utf8)
            case ("/bin/launchctl", "bootstrap"):
                guard !bootstrapFails else { throw CocoaError(.fileNoSuchFile) }
                loaded = true
                return Data()
            case ("/bin/launchctl", "bootout"):
                loaded = false
                return Data()
            case ("/usr/bin/defaults", "export"):
                guard !loginWindowUnreadable else { throw CocoaError(.fileNoSuchFile) }
                let settings: [String: Any] = autoLogin.map { ["autoLoginUser": $0] } ?? [:]
                return try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
            default: return Data()
            }
        }
    }
}

final class AutostartTests: XCTestCase {
    private let home = "/Users/k"
    private let box = "/Users/k/metaservice-box"
    private var plistPath: String { "\(home)/Library/LaunchAgents/io.metaservice.agent.plist" }

    private func make() -> (AutostartService, FakeFiles, FakeMac) {
        let files = FakeFiles()
        files.data["\(box)/start.sh"] = Data(startScript.utf8)
        let mac = FakeMac()
        return (AutostartService(files: files, run: mac.run, home: home, box: box, uid: 501), files, mac)
    }

    private func job(_ files: FakeFiles) throws -> [String: Any] {
        let data = try XCTUnwrap(files.data[plistPath])
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }

    func testThePlistRoundTripsWithTheSameArgumentsAsStartSh() throws {
        let arguments = try AutostartPlist.startArguments(startScript: startScript)
        XCTAssertEqual(arguments, ["run", "--state-dir", "state", "--engine", "apple", "--port", "9101", "--bind", "127.0.0.1", "--chat-port", "9200", "--chat-bind", "127.0.0.1", "--heartbeat-seconds", "5"])
        let data = try AutostartPlist.plistData(box: box, arguments: arguments)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).hasPrefix("<?xml"), "an XML plist")
        let job = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        XCTAssertEqual(job["Label"] as? String, "io.metaservice.agent")
        XCTAssertEqual(job["ProgramArguments"] as? [String], ["\(box)/bin/metaservice-agent"] + arguments)
        XCTAssertEqual(job["WorkingDirectory"] as? String, box)
        XCTAssertEqual(job["RunAtLoad"] as? Bool, true)
        XCTAssertEqual((job["KeepAlive"] as? [String: Any])?["SuccessfulExit"] as? Bool, false, "a clean stop by stop.sh stays stopped")
        XCTAssertEqual(job["StandardOutPath"] as? String, "\(box)/logs/agent.log")
        XCTAssertEqual(job["StandardErrorPath"] as? String, "\(box)/logs/agent.log")
        XCTAssertNil(job["UserName"])
    }

    func testAnOddBoxIsDataNotMarkup() throws {
        let data = try AutostartPlist.plistData(box: "/Users/a<b>&\"c", arguments: ["run", "--name", "x</string><key>Evil</key>"])
        let job = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        XCTAssertEqual(job["WorkingDirectory"] as? String, "/Users/a<b>&\"c")
        XCTAssertNil(job["Evil"])
        XCTAssertEqual((job["ProgramArguments"] as? [String])?.last, "x</string><key>Evil</key>")
    }

    func testTheStartLineIsReadLikeSh() throws {
        let script = "nohup ./bin/metaservice-agent run --state-dir 'my state' --name \"a b\" x\\ y >> logs/agent.log 2>&1 &\n"
        XCTAssertEqual(try AutostartPlist.startArguments(startScript: script), ["run", "--state-dir", "my state", "--name", "a b", "x y"])
        XCTAssertThrowsError(try AutostartPlist.startArguments(startScript: "echo hi\n"))
        XCTAssertThrowsError(try AutostartPlist.startArguments(startScript: "nohup ./bin/metaservice-agent enroll x >> a &\n"))
        XCTAssertThrowsError(try AutostartPlist.startArguments(startScript: "nohup ./bin/metaservice-agent run 'open >> a\n"))
    }

    func testOnWritesTheAgentAndLoadsItWhenNothingRuns() async throws {
        let (service, files, mac) = make()
        let outcome = try await service.perform(.on)
        XCTAssertEqual(outcome.code, 0)
        XCTAssertEqual(try job(files)["Label"] as? String, "io.metaservice.agent")
        XCTAssertTrue(mac.calls.contains("/bin/launchctl bootstrap gui/501 \(plistPath)"))
        XCTAssertTrue(outcome.lines.contains { $0.contains("launchd started one") })
    }

    func testOnDoesNotStartASecondCopyBesideTheHelperOfStartSh() async throws {
        let (service, files, mac) = make()
        files.data["\(box)/state/agent.pid"] = Data("4242\n".utf8)
        files.alive = [4242]
        let outcome = try await service.perform(.on)
        XCTAssertEqual(outcome.code, 0)
        XCTAssertNotNil(files.data[plistPath], "the file is still written")
        XCTAssertFalse(mac.calls.contains { $0.contains("bootstrap") }, "\(mac.calls)")
        XCTAssertTrue(outcome.lines.contains { $0.contains("next login or restart") })
    }

    func testAStalePidFileDoesNotCountAndOnTwiceChangesNothing() async throws {
        let (service, files, mac) = make()
        files.data["\(box)/state/agent.pid"] = Data("4242\n".utf8)
        _ = try await service.perform(.on)
        XCTAssertEqual(mac.calls.filter { $0.contains("bootstrap") }.count, 1)
        let first = files.data[plistPath]
        let again = try await service.perform(.on)
        XCTAssertEqual(files.data[plistPath], first)
        XCTAssertEqual(mac.calls.filter { $0.contains("bootstrap") }.count, 1, "already loaded: not loaded again")
        XCTAssertEqual(again.lines.first, "The start-at-login file was already in place.")
        XCTAssertEqual(again.code, 0)
    }

    func testWithoutAutomaticLoginOnExitsThreeWithOnePlainLine() async throws {
        let (service, files, mac) = make()
        mac.autoLogin = nil
        let outcome = try await service.perform(.on)
        XCTAssertEqual(outcome.code, 3)
        XCTAssertNotNil(files.data[plistPath])
        XCTAssertEqual(outcome.lines.filter { $0.contains("automatic login") }.count, 1)
        mac.loginWindowUnreadable = true
        let unknown = try await service.perform(.on)
        XCTAssertEqual(unknown.code, 3, "not knowing is not a pass")
    }

    func testOnFailsPlainlyWhenLaunchdRefusesOrStartShIsMissing() async throws {
        let (service, files, mac) = make()
        mac.bootstrapFails = true
        do { _ = try await service.perform(.on); XCTFail("should throw") } catch { XCTAssertTrue("\(error)".contains("launchd did not accept")) }
        files.data["\(box)/start.sh"] = nil
        do { _ = try await service.perform(.on); XCTFail("should throw") } catch { XCTAssertTrue("\(error)".contains("start.sh")) }
    }

    func testStatusIsOneJsonLineAndChangesNothing() async throws {
        let (service, files, mac) = make()
        func status() async throws -> [String: Any] {
            let outcome = try await service.perform(.status)
            XCTAssertEqual(outcome.lines.count, 1)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(outcome.lines[0].utf8)) as? [String: Any])
        }
        var before = try await status()
        XCTAssertEqual(before["unit_written"] as? Bool, false)
        XCTAssertEqual(before["effective"] as? Bool, false)
        XCTAssertEqual(before["autologin"] as? Bool, true)
        XCTAssertNil(files.data[plistPath])
        XCTAssertFalse(mac.calls.contains { $0.contains("bootstrap") || $0.contains("bootout") })
        _ = try await service.perform(.on)
        before = try await status()
        XCTAssertEqual(before["effective"] as? Bool, true)
        XCTAssertEqual(before["loaded"] as? Bool, true)
        XCTAssertEqual(before["running_by_launchd"] as? Bool, true)
        mac.autoLogin = nil
        let noLogin = try await status()
        XCTAssertEqual(noLogin["effective"] as? Bool, false)
        XCTAssertEqual(noLogin["autologin"] as? Bool, false)
    }

    func testOffBootsOutRemovesTheFileAndStartsTheHelperAgain() async throws {
        let (service, files, mac) = make()
        _ = try await service.perform(.on)
        mac.calls = []
        let outcome = try await service.perform(.off)
        XCTAssertEqual(outcome.code, 0)
        XCTAssertNil(files.data[plistPath])
        XCTAssertEqual(mac.calls.filter { $0.contains("bootout") }.count, 1)
        XCTAssertTrue(mac.calls.contains("/bin/sh \(box)/start.sh"), "the helper must not go dark")
        let again = try await service.perform(.off)
        XCTAssertEqual(again.code, 0, "off twice is fine")
    }

    func testNothingIsWrittenOutsideTheHomeOrTheBox() async throws {
        let (service, files, _) = make()
        _ = try await service.perform(.on)
        _ = try await service.perform(.off)
        XCTAssertTrue(files.data.keys.allSatisfy { $0.hasPrefix(home) })
    }
}
