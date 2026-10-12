import XCTest
@testable import RootCore

final class WireGuardTests: XCTestCase {
    func testKeysAreBase64OfThirtyTwoBytesAndMatch() {
        let pair = WireGuardKeyPair.generate()
        XCTAssertEqual(pair.privateKey.count, 44)
        XCTAssertTrue(WireGuardKeyPair.isValidPublicKey(pair.publicKey))
        XCTAssertEqual(WireGuardKeyPair.publicKey(forPrivate: pair.privateKey), pair.publicKey)
        XCTAssertNotEqual(WireGuardKeyPair.generate().privateKey, pair.privateKey)
        XCTAssertNil(WireGuardKeyPair.publicKey(forPrivate: "not a key"))
    }

    func testKnownKeyFromTheWireGuardTestVectors() throws {
        // RFC 7748 section 6.1: Alice's private key and public key.
        let private_ = Data(hex: "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a").base64EncodedString()
        XCTAssertEqual(WireGuardKeyPair.publicKey(forPrivate: private_), Data(hex: "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a").base64EncodedString())
    }

    func testAddressesAreHandedOutInOrderAndNeverTwice() throws {
        let network = WireGuardNetwork.standard
        XCTAssertEqual(try network.nextAddress(taken: []), "10.99.0.2")
        XCTAssertEqual(try network.nextAddress(taken: ["10.99.0.2", "10.99.0.4"]), "10.99.0.3")
        let all = Set((2...254).map { "10.99.0.\($0)" })
        XCTAssertThrowsError(try network.nextAddress(taken: all)) { XCTAssertEqual($0 as? WireGuardError, .noFreeAddress) }
    }

    func testTheHubOnlyAllowsEachMachineItsOwnAddress() throws {
        let hub = WireGuardKeyPair.generate(), one = WireGuardKeyPair.generate()
        let text = try WireGuardNetwork.standard.hubConfig(privateKey: hub.privateKey, peers: [.init(name: "office-mini", publicKey: one.publicKey, address: "10.99.0.2")])
        XCTAssertTrue(text.contains("AllowedIPs = 10.99.0.2/32"))
        XCTAssertTrue(text.contains("ListenPort = 51820"))
        XCTAssertThrowsError(try WireGuardNetwork.standard.hubConfig(privateKey: hub.privateKey, peers: [.init(name: "bad", publicKey: "x", address: "10.99.0.3")]))
    }

    func testAMachineReachesOnlyTheParent() throws {
        let hub = WireGuardKeyPair.generate(), machine = WireGuardKeyPair.generate()
        let text = try WireGuardNetwork.standard.machineConfig(privateKey: machine.privateKey, address: "10.99.0.2", hubPublicKey: hub.publicKey, hubEndpoint: "192.168.100.40")
        XCTAssertTrue(text.contains("AllowedIPs = 10.99.0.1/32"))
        XCTAssertTrue(text.contains("Endpoint = 192.168.100.40:51820"))
        XCTAssertTrue(text.contains("PersistentKeepalive = 25"))
        XCTAssertFalse(text.contains("0.0.0.0/0"), "never routes the machine's other traffic through the parent")
    }

    func testConnectedComesFromTheLastHandshake() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let output = "AAAA\t999900\nBBBB\t0\nCCCC\t999000\n"
        let handshakes = WireGuardHandshake.parse(output)
        XCTAssertEqual(WireGuardHandshake.state(of: "AAAA", handshakes: handshakes, now: now), .connected(since: Date(timeIntervalSince1970: 999_900)))
        XCTAssertEqual(WireGuardHandshake.state(of: "BBBB", handshakes: handshakes, now: now), .offline(reason: "no handshake yet"))
        XCTAssertEqual(WireGuardHandshake.state(of: "CCCC", handshakes: handshakes, now: now), .offline(reason: "last handshake too old"))
        XCTAssertEqual(WireGuardHandshake.parse("garbage\n\n"), [:])
    }
}

private extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}
