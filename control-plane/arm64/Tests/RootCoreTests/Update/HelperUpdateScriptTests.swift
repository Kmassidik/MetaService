import XCTest
@testable import RootCore

final class HelperUpdateScriptTests: XCTestCase {
    private let build = String(repeating: "c", count: 64)
    private func script(box: String = "/Users/kurnia/metaservice-box") throws -> String { try HelperUpdateScript.make(box: box, agentPort: 9101, expectedBuild: build) }

    func testTheScriptHoldsTheChecksumTheKeptProgramAndTheRollback() throws {
        let text = try script()
        XCTAssertTrue(text.contains(build))
        XCTAssertTrue(text.contains("made_by"), "it must check the manifest marker like the remove script")
        XCTAssertTrue(text.contains("bin/metaservice-agent.new"))
        XCTAssertTrue(text.contains("metaservice-agent.before-"))
        XCTAssertTrue(text.contains("stop.sh") && text.contains("start.sh"))
        XCTAssertTrue(text.contains("sleep \(HelperUpdateScript.settleSeconds)"))
        XCTAssertTrue(text.contains("say rolled_back") && text.contains("say rollback_failed"))
        XCTAssertFalse(text.contains("rm -rf"))
    }

    func testTheScriptTouchesTheStateFolderOnlyToReadAndRemoveThePidFile() throws {
        let lines = try script().split(separator: "\n").filter { $0.contains("state") }
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.allSatisfy { $0.contains("agent.pid") }, "\(lines)")
    }

    func testThePathsAreQuotedAndTheBuildMustBeLowercaseHex() throws {
        XCTAssertTrue(try script(box: "/tmp/it's a box").contains("'/tmp/it'\\''s a box'"))
        XCTAssertThrowsError(try HelperUpdateScript.make(box: "/b", agentPort: 9101, expectedBuild: "$(reboot)"))
        XCTAssertThrowsError(try HelperUpdateScript.make(box: "/b", agentPort: 9101, expectedBuild: build.uppercased()))
    }

    func testTheScriptIsTheSameEveryTimeForTheSameThings() throws {
        XCTAssertEqual(try script(), try script())
    }

    func testEveryAnswerTheScriptCanGiveHasPlainWords() {
        for code in HelperUpdateScript.codes {
            let result = HelperUpdateScript.outcome(output: "noise\nms-code: \(code)\n")
            XCTAssertFalse(result.message.isEmpty, code)
            XCTAssertTrue(["updated", "rolled_back", "failed"].contains(result.result), code)
        }
    }

    /// The update turns autostart on for the NEW program only once it answered, and never before the replacement or in the rollback branch.
    func testAutostartRunsForTheNewProgramAfterItAnsweredAndNeverBeforeOrInTheRollback() throws {
        let text = try script()
        let replaced = try XCTUnwrap(text.range(of: "mv -f bin/metaservice-agent.new bin/metaservice-agent"))
        let started = try XCTUnwrap(text.range(of: "sh ./start.sh", range: replaced.upperBound..<text.endIndex))
        let answered = try XCTUnwrap(text.range(of: "if alive; then", range: started.upperBound..<text.endIndex))
        let autostart = try XCTUnwrap(text.range(of: "./bin/metaservice-agent autostart on --box \"$box\"", range: answered.upperBound..<text.endIndex))
        let rollback = try XCTUnwrap(text.range(of: "cp -p \"$keep\" bin/metaservice-agent"))
        XCTAssertLessThan(autostart.lowerBound, rollback.lowerBound, "never in the rollback branch")
        XCTAssertEqual(text.components(separatedBy: "autostart on").count - 1, 1, "exactly once")
        XCTAssertTrue(text.contains("say updated_no_autostart"), "any other exit code is a note, not a failure")
        XCTAssertTrue(text.contains(">> logs/agent.log 2>&1; rc=$?"), "the helper's own reason goes to the log")
    }

    func testAutostartThatNeedsTheOwnerOrFailsStillCountsAsUpdatedWithAPlainSentence() {
        let sudo = HelperUpdateScript.outcome(output: "ms-code: updated_linger\n", login: "kurnia")
        XCTAssertEqual(sudo.result, "updated")
        XCTAssertTrue(sudo.message.contains("`sudo loginctl enable-linger kurnia`"), sudo.message)
        XCTAssertFalse(HelperUpdateScript.outcome(output: "ms-code: updated_linger\n", login: "a b; reboot").message.contains("reboot"))
        let mac = HelperUpdateScript.outcome(output: "ms-code: updated_autologin\n")
        XCTAssertEqual(mac.result, "updated")
        XCTAssertTrue(mac.message.contains("automatic login"), mac.message)
        let failed = HelperUpdateScript.outcome(output: "ms-code: updated_no_autostart\n")
        XCTAssertEqual(failed.result, "updated")
        XCTAssertTrue(failed.message.contains("could not be set to start again by itself") && failed.message.contains("logs/agent.log"), failed.message)
        XCTAssertTrue(HelperUpdateScript.outcome(output: "ms-code: updated\n").message.contains("starts again by itself"))
    }

    func testTheResultNamesMatchWhatHappened() {
        XCTAssertEqual(HelperUpdateScript.outcome(output: "ms-code: updated\n").result, "updated")
        XCTAssertEqual(HelperUpdateScript.outcome(output: "ms-code: rolled_back\n").result, "rolled_back")
        XCTAssertEqual(HelperUpdateScript.outcome(output: "ms-code: checksum\n").result, "failed")
        XCTAssertEqual(HelperUpdateScript.outcome(output: "ms-code: rollback_failed\n").result, "failed")
    }

    func testTextFromTheOtherComputerIsNeverShownAndAnUnknownCodeIsAFailure() {
        let result = HelperUpdateScript.outcome(output: "ms-code: <script>alert(1)</script>\nanything")
        XCTAssertEqual(result.result, "failed")
        XCTAssertFalse(result.message.contains("script"))
        XCTAssertEqual(HelperUpdateScript.outcome(output: "").result, "failed")
        XCTAssertEqual(HelperUpdateScript.outcome(output: "ms-code: updated\nms-code: checksum\n").result, "failed", "the last word counts")
    }
}
