import XCTest
@testable import RootCore

/// The owner's allowlist for Add machine: the parser (ROOT_REMOTE_EXTRA_ADDRESSES) and the rule that uses it.
final class RemoteExtraAddressesTests: XCTestCase {
    func testRemoteExtraParsesAGoodList() {
        XCTAssertEqual(RemoteExtraAddresses.parse("202.51.196.202,203.0.113.5"), ["202.51.196.202", "203.0.113.5"])
    }

    func testRemoteExtraTrimsSpacesAndIgnoresEmptyItems() {
        XCTAssertEqual(RemoteExtraAddresses.parse(" 202.51.196.202 , ,, 203.0.113.5 ,"), ["202.51.196.202", "203.0.113.5"])
    }

    func testRemoteExtraDropsDuplicates() {
        XCTAssertEqual(RemoteExtraAddresses.parse("202.51.196.202,202.51.196.202, 202.51.196.202"), ["202.51.196.202"])
    }

    func testRemoteExtraSkipsBadTextWithoutFailing() {
        XCTAssertEqual(RemoteExtraAddresses.parse("not-an-ip,300.1.1.1,202.51.196.202,example.com,1.2.3"), ["202.51.196.202"])
    }

    func testRemoteExtraDropsLoopbackUnspecifiedAndBroadcast() {
        XCTAssertEqual(RemoteExtraAddresses.parse("127.0.0.1,127.9.9.9,0.0.0.0,255.255.255.255,202.51.196.202"), ["202.51.196.202"])
    }

    func testRemoteExtraKeepsAtMostEightAddresses() {
        let items = (1...10).map { "203.0.113.\($0)" }
        let parsed = RemoteExtraAddresses.parse(items.joined(separator: ","))
        XCTAssertEqual(parsed.count, RemoteExtraAddresses.maxCount)
        XCTAssertEqual(parsed.count, 8)
    }

    func testRemoteExtraEmptyStringGivesAnEmptySet() {
        XCTAssertEqual(RemoteExtraAddresses.parse(""), [])
        XCTAssertEqual(RemoteExtraAddresses.parse("  ,  "), [])
    }

    func testRemoteExtraPublicAddressIsRefusedWithAnEmptyList() {
        XCTAssertFalse(RemoteTarget.allowed(address: "202.51.196.202", allowLoopback: false, subnet: nil, extra: []))
    }

    func testRemoteExtraListedPublicAddressIsAllowed() {
        let extra = RemoteExtraAddresses.parse("202.51.196.202")
        XCTAssertTrue(RemoteTarget.allowed(address: "202.51.196.202", allowLoopback: false, subnet: nil, extra: extra))
    }

    func testRemoteExtraADifferentPublicAddressIsStillRefused() {
        let extra = RemoteExtraAddresses.parse("202.51.196.202")
        XCTAssertFalse(RemoteTarget.allowed(address: "202.51.196.203", allowLoopback: false, subnet: nil, extra: extra))
        XCTAssertFalse(RemoteTarget.allowed(address: "202.51.196.2", allowLoopback: false, subnet: nil, extra: extra))
    }

    func testRemoteExtraPrivateAddressOutsideTheSubnetIsAllowedOnlyWhenListed() {
        let subnet = Subnet(cidr: "192.168.100.0/24")
        XCTAssertFalse(RemoteTarget.allowed(address: "192.168.101.40", allowLoopback: false, subnet: subnet, extra: []))
        XCTAssertTrue(RemoteTarget.allowed(address: "192.168.101.40", allowLoopback: false, subnet: subnet, extra: ["192.168.101.40"]))
    }

    func testRemoteExtraLoopbackIsStillRefusedWhenListedAndLoopbackIsOff() {
        XCTAssertFalse(RemoteTarget.allowed(address: "127.0.0.1", allowLoopback: false, subnet: nil, extra: ["127.0.0.1"]))
        XCTAssertTrue(RemoteTarget.allowed(address: "127.0.0.1", allowLoopback: true, subnet: nil, extra: []))
    }
}
