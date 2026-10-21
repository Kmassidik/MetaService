import XCTest
@testable import RootCore

final class TerminalSupportTests: XCTestCase {
    func testOnlyAMacHasAConsole() {
        XCTAssertTrue(TerminalSupport.isSupported(machineOS: "macos"))
        for other in ["linux", "windows", "", "Darwin", "MACOS"] { XCTAssertFalse(TerminalSupport.isSupported(machineOS: other), other) }
    }
}
