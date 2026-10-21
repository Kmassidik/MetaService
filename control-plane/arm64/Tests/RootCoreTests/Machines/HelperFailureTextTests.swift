import XCTest
@testable import RootCore

final class HelperFailureTextTests: XCTestCase {
    func testAShortReasonKeepsItsLinesAndWords() {
        let text = "The VM did not start.\nTry 1, with systemd: it stopped right after it started (exit code 255)."
        XCTAssertEqual(HelperFailureText.clean(text), text)
    }

    func testEscapeSequencesControlCharactersAndSizeAreHandledAgain() {
        let hostile = "\u{1B}[31mbad\u{1B}[0m\u{00}\n" + String(repeating: "x", count: 20_000)
        let cleaned = HelperFailureText.clean(hostile)
        XCTAssertLessThanOrEqual(cleaned.utf8.count, HelperFailureText.maxBytes)
        XCTAssertFalse(cleaned.contains("\u{1B}") || cleaned.contains("\u{00}"))
    }

    func testOnlyTheErrorEntryOfAResultIsCleaned() {
        let result = HelperFailureText.cleanResult(["error": "a\u{07}b", "workload_id": "w-1", "port": "9200"])
        XCTAssertEqual(result, ["error": "ab", "workload_id": "w-1", "port": "9200"])
        XCTAssertEqual(HelperFailureText.cleanResult(["workload_id": "w-1"]), ["workload_id": "w-1"], "no error entry is made up")
    }
}
