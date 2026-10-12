import XCTest
@testable import RootCore

final class ParentUrlTests: XCTestCase {
    private let locals = ["192.168.1.7", "192.168.100.40", "10.0.0.5"]

    func testALoopbackTargetReachesTheParentOnLoopback() {
        XCTAssertEqual(ParentUrl.make(bind: "127.0.0.1", port: 9102, target: "127.0.0.1", localAddresses: locals), "http://127.0.0.1:9102")
    }

    func testARealComputerNeedsTheParentToListenOnTheNetwork() {
        XCTAssertNil(ParentUrl.make(bind: "127.0.0.1", port: 9102, target: "192.168.100.50", localAddresses: locals), "bound to this computer only: nobody else can reach it")
        XCTAssertEqual(ParentUrl.make(bind: "192.168.100.40", port: 9102, target: "192.168.100.50", localAddresses: locals), "http://192.168.100.40:9102")
    }

    func testAnyAddressUsesTheAddressOnTheTargetsNetwork() {
        XCTAssertEqual(ParentUrl.make(bind: "0.0.0.0", port: 9102, target: "192.168.100.50", localAddresses: locals), "http://192.168.100.40:9102")
        XCTAssertEqual(ParentUrl.make(bind: "0.0.0.0", port: 9102, target: "10.0.0.99", localAddresses: locals), "http://10.0.0.5:9102")
        XCTAssertNil(ParentUrl.make(bind: "0.0.0.0", port: 9102, target: "172.16.0.9", localAddresses: locals), "no address of this computer is on that network")
    }

    func testANonsenseBindIsRefused() {
        for bind in ["", "localhost", "not-an-ip", "999.1.1.1"] { XCTAssertNil(ParentUrl.make(bind: bind, port: 9102, target: "192.168.100.50", localAddresses: locals), bind) }
    }
}
