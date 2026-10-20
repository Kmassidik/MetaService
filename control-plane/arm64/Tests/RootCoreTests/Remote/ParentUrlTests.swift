import XCTest
@testable import RootCore

final class ParentUrlTests: XCTestCase {
    func testAnAgentAlwaysFindsTheParentOnItsOwnLoopback() {
        XCTAssertEqual(ParentUrl.make(port: 9102), "http://127.0.0.1:9102")
        XCTAssertEqual(ParentUrl.make(port: 9777), "http://127.0.0.1:9777")
    }

    func testAComputerOnTheNetworkGetsTheReturnPath() {
        XCTAssertEqual(ParentUrl.reversePort(listenPort: 9102, target: "192.168.0.10"), 9102)
        XCTAssertEqual(ParentUrl.reversePort(listenPort: 9102, target: "10.0.0.99"), 9102)
    }

    func testThisComputerNeedsNoReturnPathBecauseTheParentIsAlreadyOnItsLoopback() {
        XCTAssertNil(ParentUrl.reversePort(listenPort: 9102, target: "127.0.0.1"))
        XCTAssertNil(ParentUrl.reversePort(listenPort: 9102, target: "127.5.5.5"))
    }
}
