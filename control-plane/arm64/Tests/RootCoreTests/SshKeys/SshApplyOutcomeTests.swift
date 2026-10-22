import XCTest
@testable import RootCore

final class SshApplyOutcomeTests: XCTestCase {
    private func read(_ status: Int?, _ json: [String: Any]?, keys: Int = 2) -> SshApplyOutcome {
        SshApplyOutcome.read(status: status, json: json, expectedKeys: keys)
    }

    func testACountThatMatchesIsApplied() {
        XCTAssertEqual(read(200, ["applied": 2, "sshd": "running", "installed": true]), .applied(sshd: "running"))
        XCTAssertEqual(read(200, ["applied": 2, "sshd": "installed"]), .applied(sshd: "installed"))
    }

    func testAnUnknownSshdWordIsDroppedNotTrusted() {
        XCTAssertEqual(read(200, ["applied": 2, "sshd": "<b>x</b>"]), .applied(sshd: nil))
        XCTAssertEqual(read(200, ["applied": 2]), .applied(sshd: nil))
    }

    func testAWrongCountOrBodyIsNotApplied() {
        XCTAssertEqual(read(200, ["applied": 1, "sshd": "running"]), .notApplied)
        XCTAssertEqual(read(200, nil), .notApplied)
        XCTAssertEqual(read(200, ["applied": "2"]), .notApplied)
    }

    func testTheHelpersInstallFailureKeepsItsPlainWords() {
        let body: [String: Any] = ["error": ["code": "sshd_install_failed", "message": "The VM could not download the SSH server."]]
        XCTAssertEqual(read(502, body), .sshdFailed(message: "The VM could not download the SSH server."))
    }

    func testAnInstallFailureWithoutWordsGetsAGenericSentence() {
        XCTAssertEqual(read(502, ["error": ["code": "sshd_install_failed"]]), .sshdFailed(message: SshdProgress.unclearFailureMessage))
    }

    func testOtherBadGatewaysAndOddStatusesAreJustNotApplied() {
        XCTAssertEqual(read(502, ["error": ["code": "unreachable", "message": "x"]]), .notApplied)
        XCTAssertEqual(read(502, nil), .notApplied)
        for status in [404, 409, 500, 429] { XCTAssertEqual(read(status, ["error": ["code": "not_running"]]), .notApplied, "\(status)") }
        XCTAssertEqual(read(nil, nil), .notApplied)
    }

    func testAHelperThatRefusesTheNewFieldIsTooOld() {
        XCTAssertEqual(read(400, ["error": ["code": "invalid_input", "message": "unknown field install_sshd"]]), .helperTooOld)
    }
}
