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
