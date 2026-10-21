import XCTest
@testable import RootCore

final class SudoPasswordTests: XCTestCase {
    private let secret = "Fake-Pass-9f3a"

    func testItPrintsAsHiddenInEveryWayItCanBePrinted() {
        let password = SudoPassword(secret)
        XCTAssertEqual("\(password)", "<hidden>")
        XCTAssertEqual(String(describing: password), "<hidden>")
        XCTAssertEqual(String(reflecting: password), "<hidden>")
        var dumped = ""
        dump(password, to: &dumped)
        XCTAssertFalse(dumped.contains(secret), "dump() must not show it")
    }

    func testStandardInputIsThePasswordAndALineEndAndNothingForAnEmptyOne() {
        XCTAssertEqual(SudoPassword(secret).standardInput(), Data((secret + "\n").utf8))
        XCTAssertTrue(SudoPassword("").standardInput().isEmpty)
        XCTAssertTrue(SudoPassword("").isEmpty)
    }

    func testRedactedBlanksEveryCopyAndLeavesOtherTextAlone() {
        let password = SudoPassword(secret)
        XCTAssertEqual(password.redacted("a \(secret) b \(secret)"), "a *** b ***")
        XCTAssertEqual(password.redacted("nothing here"), "nothing here")
        XCTAssertEqual(SudoPassword("").redacted("same"), "same")
    }

    func testWipeForgetsIt() {
        let password = SudoPassword(secret)
        password.wipe()
        XCTAssertTrue(password.isEmpty)
        XCTAssertTrue(password.standardInput().isEmpty)
        XCTAssertEqual(password.redacted(secret), secret, "nothing is kept to compare with")
    }
}
