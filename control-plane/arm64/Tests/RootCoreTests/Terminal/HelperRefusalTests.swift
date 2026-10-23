import XCTest
@testable import RootCore

final class HelperRefusalTests: XCTestCase {
    func testEachHelperRefusalHasItsOwnPlainReason() {
        XCTAssertEqual(HelperRefusal.reason(code: "not_running"), .vmStopped)
        XCTAssertEqual(HelperRefusal.reason(code: "console_open").text, "this workload already has a console")
        XCTAssertEqual(HelperRefusal.reason(code: "no_agent").text, "this VM has no incus agent, so the console cannot open")
        XCTAssertEqual(HelperRefusal.reason(code: "no_agent").code, CloseReason.internalCode)
    }

    func testAnAnswerWithoutAKnownCodeUsesTheGenericWords() {
        XCTAssertEqual(HelperRefusal.reason(code: nil), .vmUnavailable)
        XCTAssertEqual(HelperRefusal.reason(code: "not_found"), .vmUnavailable)
    }
}
