import XCTest
@testable import RootCore

final class HelperAutostartTests: XCTestCase {
    func testTheInstallLineRunsTheVerbInTheBoxAndAlwaysEndsWithTheExitMarker() {
        let line = HelperAutostart.installScript(box: "/home/kurnia/metaservice-box")
        XCTAssertTrue(line.contains("cd '/home/kurnia/metaservice-box' && ./bin/metaservice-agent autostart on --box '/home/kurnia/metaservice-box' >> logs/agent.log 2>&1;"), line)
        XCTAssertTrue(line.contains("echo \"ms-autostart-exit: $?\""), "the marker comes after the verb whatever it did")
        XCTAssertTrue(HelperAutostart.installScript(box: "/tmp/it's a box").contains("'/tmp/it'\\''s a box'"), "paths are quoted")
        XCTAssertFalse(line.contains("sudo"))
    }

    func testTheExitCodeIsTheWholeAnswer() {
        XCTAssertEqual(HelperAutostart.result(output: "ms-autostart-exit: 0\nms-autostart-system: Linux\n"), .effective)
        XCTAssertEqual(HelperAutostart.result(output: "ms-autostart-exit: 3\n"), .needsOwner)
        XCTAssertEqual(HelperAutostart.result(output: "ms-autostart-exit: 1\n"), .failed)
        XCTAssertEqual(HelperAutostart.result(output: "ms-autostart-exit: 127\n"), .failed)
        XCTAssertEqual(HelperAutostart.result(output: ""), .failed, "no marker is a failure")
        XCTAssertEqual(HelperAutostart.result(output: "ms-autostart-exit: banana\n"), .failed)
        XCTAssertEqual(HelperAutostart.result(output: "ms-autostart-exit: 0\nms-autostart-exit: 3\n"), .needsOwner, "the last marker counts")
    }

    func testTheComputerSaysWhetherItIsAMac() {
        XCTAssertTrue(HelperAutostart.isMac(output: "ms-autostart-exit: 3\nms-autostart-system: Darwin\n"))
        XCTAssertFalse(HelperAutostart.isMac(output: "ms-autostart-exit: 3\nms-autostart-system: Linux\n"))
        XCTAssertFalse(HelperAutostart.isMac(output: ""))
    }

    func testExitThreeIsAPlainNoteWithTheOneStepForTheOwner() {
        let linux = HelperAutostart.installSentence(.needsOwner, isMac: false, login: "kurnia")
        XCTAssertTrue(linux.contains("`sudo loginctl enable-linger kurnia`"), linux)
        let mac = HelperAutostart.installSentence(.needsOwner, isMac: true, login: "kurnia")
        XCTAssertTrue(mac.contains("automatic login") && !mac.contains("sudo"), mac)
        XCTAssertFalse(linux.lowercased().contains("fail") || mac.lowercased().contains("fail"), "never worded as a failure")
    }

    func testALoginThatIsNotAPlainNameNeverReachesTheSudoLine() {
        let hostile = HelperAutostart.installSentence(.needsOwner, isMac: false, login: "a; rm -rf /")
        XCTAssertFalse(hostile.contains("rm -rf"), hostile)
        XCTAssertTrue(hostile.contains("enable-linger <login>"))
    }

    func testTheOtherWordsAreFixedText() {
        XCTAssertTrue(HelperAutostart.installSentence(.effective, isMac: false, login: "k").contains("starts again by itself"))
        let failed = HelperAutostart.installSentence(.failed, isMac: false, login: "k")
        XCTAssertTrue(failed.contains("logs/agent.log") && failed.contains("start.sh"), failed)
    }

    func testTheInstallPlanNoLongerSaysTheMachineStaysOfflineAfterARestart() {
        let options = RemoteInstallOptions.defaults(name: "mini", home: "/home/k", engine: "incus", rootURL: "http://127.0.0.1:9100")
        let plan = try! InstallPlan.make(options, agentSize: nil)
        let text = plan.steps.first { $0.id == "start" }!.changes.joined(separator: " ")
        XCTAssertFalse(text.contains("does not start again by itself"), text)
        XCTAssertTrue(text.contains("systemd user unit") && text.contains("LaunchAgent") && text.contains("no admin rights"), text)
    }

    func testTheBoxRemovalTakesTheUserUnitAwayWithoutSudoAndBeforeStopSh() throws {
        let script = PlanScripts.removeScript(box: "/home/k/metaservice-box", key: nil)
        for part in ["$HOME/.config/systemd/user/metaservice-agent.service", "systemctl --user disable --now metaservice-agent", "systemctl --user daemon-reload"] {
            XCTAssertTrue(script.contains(part), part)
        }
        for line in script.split(separator: "\n") where line.contains("systemctl --user") {
            XCTAssertFalse(line.contains("sudo"), "\(line)")
        }
        let unit = try XCTUnwrap(script.range(of: "systemctl --user disable"))
        let stop = try XCTUnwrap(script.range(of: "stop.sh"))
        XCTAssertLessThan(unit.lowerBound, stop.lowerBound)
    }
}
