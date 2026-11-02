import XCTest
@testable import RootCore

final class HelperRefusalTests: XCTestCase {
    func testEachHelperRefusalHasItsOwnPlainReason() {
        XCTAssertEqual(HelperRefusal.reason(code: "not_running"), .vmStopped)
        XCTAssertEqual(HelperRefusal.reason(code: "console_open").text, "this workload already has a console")
        XCTAssertEqual(HelperRefusal.reason(code: "no_agent").text, "this VM is not ready for the terminal yet: its guest agent is not running")
        XCTAssertEqual(HelperRefusal.reason(code: "no_agent").code, CloseReason.internalCode)
    }

    func testAnAnswerWithoutAKnownCodeUsesTheGenericWords() {
        XCTAssertEqual(HelperRefusal.reason(code: nil), .vmUnavailable)
        XCTAssertEqual(HelperRefusal.reason(code: "not_found"), .vmUnavailable)
    }
}
