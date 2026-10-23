import XCTest
@testable import RootCore

final class AppInstallOutcomeTests: XCTestCase {
    private let sha = String(repeating: "ab", count: 32)

    private func read(_ status: Int?, _ json: [String: Any]?) -> AppInstallOutcome {
        AppInstallOutcome.read(status: status, json: json, expectedApp: "openclaw")
    }

    private func failure(message: Any = "Download failed", log: Any = ["a"]) -> [String: Any] {
        ["error": ["code": "app_install_failed", "message": message, "log_tail": log]]
    }

    func testAnInstalledAppCarriesItsVersionAndChecksum() {
        XCTAssertEqual(read(200, ["app": "openclaw", "installed": true, "version": "1.2.3", "installer_sha256": sha]), .installed(version: "1.2.3", installerSha256: sha, changed: true))
        XCTAssertEqual(read(200, ["app": "openclaw", "installed": false, "version": NSNull(), "installer_sha256": NSNull()]), .installed(version: nil, installerSha256: nil, changed: false))
    }

    func testAnAnswerThatIsNotTheContractsShapeIsNotUsed() {
        let bad: [[String: Any]?] = [nil, [:], ["app": "hermes", "installed": true], ["app": "openclaw", "installed": "yes"]]
        for item in bad { XCTAssertEqual(read(200, item), .notDone, "\(String(describing: item))") }
    }

    func testABadChecksumIsDroppedButTheInstallStillCounts() {
        XCTAssertEqual(read(200, ["app": "openclaw", "installed": true, "installer_sha256": "NOT-HEX"]), .installed(version: nil, installerSha256: nil, changed: true))
        XCTAssertEqual(read(200, ["app": "openclaw", "installed": true, "installer_sha256": sha.uppercased()]), .installed(version: nil, installerSha256: nil, changed: true))
    }

    func testAFailureKeepsThePlainMessageAndOnlyTheLastTwelveLines() {
        let lines = (1...30).map { "line \($0)" }
        guard case .failed(let message, let tail) = read(502, failure(log: lines)) else { return XCTFail("not a failure") }
        XCTAssertEqual(message, "Download failed")
        XCTAssertEqual(tail, Array(lines.suffix(12)))
    }

    func testLogLinesAreCutAndStrippedOfControlCharacters() {
        let long = String(repeating: "x", count: 500)
        guard case .failed(_, let tail) = read(502, failure(log: ["\u{1B}[31mred\u{07}", long, "", 5])) else { return XCTFail("not a failure") }
        XCTAssertEqual(tail, ["[31mred", String(repeating: "x", count: 200)])
    }

    func testAnEmptyOrMissingMessageBecomesAGenericSentence() {
        for message: Any in ["", "\n", 5] {
            XCTAssertEqual(read(502, failure(message: message)), .failed(message: "Setting up the app failed. Try again.", logTail: ["a"]), "\(message)")
        }
    }

    func testAFailureWithAnotherCodeOrShapeIsNotAnInstallFailure() {
        XCTAssertEqual(read(502, ["error": ["code": "other", "message": "x"]]), .notDone)
        XCTAssertEqual(read(502, nil), .notDone)
    }

    func testAnOldHelperAnswers404Or400() {
        XCTAssertEqual(read(404, nil), .helperTooOld)
        XCTAssertEqual(read(400, ["error": ["code": "invalid_input", "message": "x"]]), .helperTooOld)
    }

    func testAStoppedVmOrNoAnswerIsTriedAgainLater() {
        XCTAssertEqual(read(409, ["error": ["code": "not_running", "message": "x"]]), .notDone)
        XCTAssertEqual(read(nil, nil), .notDone)
        XCTAssertEqual(read(500, nil), .notDone)
    }

    func testTheAppCallWaitsTwentyFiveMinutes() {
        XCTAssertEqual(AppCatalog.callSeconds, 1500)
    }
}
