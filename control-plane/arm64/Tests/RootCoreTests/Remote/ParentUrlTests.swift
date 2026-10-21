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

    private let own = ["192.168.0.40", "10.8.0.2"]

    func testThisComputerByItsNetworkAddressNeedsNoReturnPathEither() {
        XCTAssertNil(ParentUrl.reversePort(listenPort: 9102, target: "192.168.0.40", ownAddresses: own), "the parent already holds that port on this computer, a second one cannot be opened")
        XCTAssertNil(ParentUrl.reversePort(listenPort: 9102, target: "10.8.0.2", ownAddresses: own))
        XCTAssertEqual(ParentUrl.reversePort(listenPort: 9102, target: "192.168.0.30", ownAddresses: own), 9102, "another computer still gets it")
    }

    func testAnAgentOnThisComputerCallsFromLoopbackWhateverAddressItWasAddedBy() {
        XCTAssertEqual(ParentUrl.arrivalAddress(target: "192.168.0.40", ownAddresses: own), "127.0.0.1")
        XCTAssertEqual(ParentUrl.arrivalAddress(target: "127.0.0.1", ownAddresses: own), "127.0.0.1")
        XCTAssertNil(ParentUrl.arrivalAddress(target: "192.168.0.30", ownAddresses: own), "through a return path its source is not known in advance")
    }
}
