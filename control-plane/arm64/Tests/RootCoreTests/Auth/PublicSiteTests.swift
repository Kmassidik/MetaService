import XCTest
@testable import RootCore

final class PublicSiteTests: XCTestCase {
    func testTheConnectorsAddressIsUsedOnlyWhenTheConnectionComesFromThisMachineAndTheSiteIsPublic() {
        XCTAssertEqual(ClientAddress.resolve(peer: "127.0.0.1", forwarded: "203.0.113.9", trustForwarded: true), "203.0.113.9")
        XCTAssertEqual(ClientAddress.resolve(peer: "::1", forwarded: "203.0.113.9", trustForwarded: true), "203.0.113.9")
        XCTAssertEqual(ClientAddress.resolve(peer: "127.0.0.1", forwarded: "2001:db8::1", trustForwarded: true), "2001:db8::1")
    }

    func testAConnectionFromAnywhereElseKeepsItsOwnAddressWhateverItClaims() {
        XCTAssertEqual(ClientAddress.resolve(peer: "192.168.1.20", forwarded: "203.0.113.9", trustForwarded: true), "192.168.1.20")
        XCTAssertEqual(ClientAddress.resolve(peer: "203.0.113.50", forwarded: "10.0.0.1", trustForwarded: true), "203.0.113.50")
    }

    func testAPrivateSiteNeverBelievesTheHeader() {
        XCTAssertEqual(ClientAddress.resolve(peer: "127.0.0.1", forwarded: "203.0.113.9", trustForwarded: false), "127.0.0.1")
    }

    func testJunkInTheHeaderIsIgnored() {
        let junk = ["", "not an address", "1.2.3", "203.0.113.9, 10.0.0.1", "203.0.113.9\r\nX: y", "<script>", String(repeating: "a", count: 300), ":", "::::"]
        for text in junk {
            XCTAssertEqual(ClientAddress.resolve(peer: "127.0.0.1", forwarded: text, trustForwarded: true), "127.0.0.1", text)
        }
        XCTAssertEqual(ClientAddress.resolve(peer: "127.0.0.1", forwarded: nil, trustForwarded: true), "127.0.0.1")
    }

    func testIPv6AddressesAreParsedNotGuessed() {
        for good in ["2001:db8::1", "::1", "fe80::1ff:fe23:4567:890a", "2001:db8:0:0:0:0:0:1", "::ffff:203.0.113.9", "2001:DB8::ABCD"] {
            XCTAssertTrue(ClientAddress.isAddress(good), good)
        }
        for bad in ["::::", "1:2:3:4:5:6:7:8:9", "1::2::3", "12345::1", "g::1", "1:2:3:4:5:6:7", ":1:2:3:4:5:6:7", "1:2:3:4:5:6:7:", "::ffff:999.1.1.1", "1:::2"] {
            XCTAssertFalse(ClientAddress.isAddress(bad), bad)
        }
    }

    func testAPublicPanelAsksForALongerAdminPassword() {
        XCTAssertEqual(PasswordHash.minimumLength(publicSite: false), 8)
        XCTAssertEqual(PasswordHash.minimumLength(publicSite: true), 12)
        XCTAssertGreaterThan(PasswordHash.minLengthPublic, PasswordHash.minLength)
    }
}
