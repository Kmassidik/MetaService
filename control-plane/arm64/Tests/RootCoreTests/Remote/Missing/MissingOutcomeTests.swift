import XCTest
@testable import RootCore

final class MissingOutcomeTests: XCTestCase {
    private let password = SudoPassword("Fake-Pass-9f3a")

    private func read(_ status: Int32, _ output: String = "", _ errors: String = "") -> MissingFailure? {
        MissingOutcome.read(status: status, output: output, errors: errors, password: password)
    }

    func testTheDoneMarkerWithStatusZeroIsSuccess() {
        XCTAssertNil(read(0, "ms-sudo-ok\nms-done\n"))
    }

    func testSudoRefusalsAreToldApart() {
        XCTAssertEqual(read(1, "", "sudo: 1 incorrect password attempt"), .wrongPassword)
        XCTAssertEqual(read(1, "", "Sorry, try again.\nsudo: 3 incorrect password attempts"), .wrongPassword)
        XCTAssertEqual(read(1, "", "sudo: no password was provided"), .wrongPassword)
        XCTAssertEqual(read(1, "", "sudo-rs: Authentication failed, try again."), .wrongPassword)
        XCTAssertEqual(read(1, "", "build is not in the sudoers file.  This incident will be reported."), .notAllowed)
        XCTAssertEqual(read(1, "", "Sorry, user build is not allowed to execute '/bin/sh' as root"), .notAllowed)
        XCTAssertEqual(read(1, "", "sudo: a password is required"), .needsPassword)
        XCTAssertEqual(read(1, "", "sudo: no tty present and no askpass program specified"), .needsTerminal)
        XCTAssertEqual(read(127, "", "sh: 1: sudo: not found"), .noSudo)
        XCTAssertEqual(read(1, "", "something odd"), .unknown)
    }

    func testAScriptFailureCarriesItsOwnWordsWithoutThePassword() {
        let output = "ms-sudo-ok\nms-error: installing incus did not work with Fake-Pass-9f3a\nms-detail: E: Unable to locate package\n"
        guard case .stopped(let text)? = read(1, output) else { return XCTFail("not a script failure") }
        XCTAssertTrue(text.contains("installing incus did not work"))
        XCTAssertTrue(text.contains("Unable to locate package"))
        XCTAssertFalse(text.contains("Fake-Pass-9f3a"))
    }

    func testAScriptThatStoppedWithoutAReasonIsUnknownNotSuccess() {
        XCTAssertEqual(read(1, "ms-sudo-ok\n"), .stopped(MissingFailure.unknown.message))
        XCTAssertNotNil(read(0, "ms-sudo-ok\n"), "no done marker means it did not finish")
    }

    func testNoMessageEverHoldsAPasswordPlaceholder() {
        for failure in [MissingFailure.wrongPassword, .notAllowed, .needsPassword, .needsTerminal, .noSudo, .unknown] { XCTAssertFalse(failure.message.isEmpty) }
    }
}
