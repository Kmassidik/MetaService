import XCTest
@testable import RootCore

final class RemoteTargetTests: XCTestCase {
    func testAnAddressAndAHostNameAreAccepted() throws {
        let byAddress = try RemoteTarget(host: "192.168.100.40", user: "kurnia")
        XCTAssertEqual([byAddress.host, String(byAddress.port), byAddress.user], ["192.168.100.40", "22", "kurnia"])
        XCTAssertTrue(byAddress.isAddress)
        let byName = try RemoteTarget(host: "  Office-Mini.local ", port: 2222, user: "_build")
        XCTAssertEqual([byName.host, String(byName.port)], ["office-mini.local", "2222"])
        XCTAssertFalse(byName.isAddress)
    }

    func testAHostOrUserThatCouldBeReadAsAnSshOptionIsRefused() {
        for host in ["-oProxyCommand=evil", "-v", "a b", "a;b", "a$(b)", "host name", "", "a/b", "a@b"] {
            XCTAssertThrowsError(try RemoteTarget(host: host, user: "kurnia"), host) { XCTAssertEqual($0 as? RemoteTargetError, .badHost) }
        }
        for user in ["-oProxyCommand=evil", "a b", "", "root;ls", "a@b", "1abc", String(repeating: "a", count: 33)] {
            XCTAssertThrowsError(try RemoteTarget(host: "10.0.0.5", user: user), user) { XCTAssertEqual($0 as? RemoteTargetError, .badUser) }
        }
    }

    func testThePortMustBeARealPort() {
        for port in [0, -1, 65536, 100000] { XCTAssertThrowsError(try RemoteTarget(host: "10.0.0.5", port: port, user: "u"), String(port)) { XCTAssertEqual($0 as? RemoteTargetError, .badPort) } }
        XCTAssertEqual(try RemoteTarget(host: "10.0.0.5", port: 65535, user: "u").port, 65535)
    }

    func testOnlyPrivateAddressesOnTheParentsNetworkAreAllowed() throws {
        let subnet = Subnet(cidr: "192.168.100.0/24")
        XCTAssertTrue(RemoteTarget.allowed(address: "192.168.100.40", allowLoopback: false, subnet: subnet))
        XCTAssertFalse(RemoteTarget.allowed(address: "192.168.101.40", allowLoopback: false, subnet: subnet), "another network")
        XCTAssertFalse(RemoteTarget.allowed(address: "8.8.8.8", allowLoopback: false, subnet: subnet))
        XCTAssertFalse(RemoteTarget.allowed(address: "202.72.223.27", allowLoopback: false, subnet: nil), "a public address, even with no subnet known")
        XCTAssertTrue(RemoteTarget.allowed(address: "10.1.2.3", allowLoopback: false, subnet: nil))
        XCTAssertFalse(RemoteTarget.allowed(address: "999.1.1.1", allowLoopback: true, subnet: nil))
    }

    func testLoopbackIsAllowedOnlyWhenTurnedOn() {
        XCTAssertFalse(RemoteTarget.allowed(address: "127.0.0.1", allowLoopback: false, subnet: nil))
        XCTAssertTrue(RemoteTarget.allowed(address: "127.0.0.1", allowLoopback: true, subnet: nil))
    }
}
