import CryptoKit
import Foundation
import XCTest
@testable import RootCore

/// The port host's label: 16 characters of lowercase base32 over the first 80 bits of the Root's signature for
/// (sandbox, port). See `sandbox/README.md`, "Addresses".
final class PortHostsTests: XCTestCase {
    private let sandbox = "abcdefghij0123456789"
    private let signature = "f0e1d2c3b4a5968778695a4b3c2d1e0f1a2b3c4d5e6f708192a3b4c5d6e7f809"

    /// A vector worked out on its own (RFC 4648 base32 of the first ten signature bytes, lowercased), so a change to the
    /// derivation is caught and not just compared with itself.
    func testAKnownSignatureGivesAKnownLabel() {
        XCTAssertEqual(PortHosts.label(from: signature), "6dq5fq5uuwlio6dj")
        XCTAssertEqual(PortHosts.label(from: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"), "aerukz4jvpg66ajd")
        XCTAssertEqual(PortHosts.label(from: String(repeating: "0", count: 64)), "aaaaaaaaaaaaaaaa")
    }

    func testALabelIsSixteenCharactersOfLowercaseBase32() throws {
        let label = try XCTUnwrap(PortHosts.label(from: signature))
        XCTAssertEqual(label.count, PortHosts.labelCharacters)
        XCTAssertEqual(PortHosts.labelCharacters, 16)
        XCTAssertTrue(label.allSatisfy(PortHosts.alphabet.contains))
        XCTAssertEqual(PortHosts.alphabet, Array("abcdefghijklmnopqrstuvwxyz234567"))
        XCTAssertTrue(PortHosts.isLabel(label))
    }

    func testTheSameSignatureAlwaysGivesTheSameLabel() {
        let labels = Set((0..<20).map { _ in PortHosts.label(from: signature) })
        XCTAssertEqual(labels, [PortHosts.label(from: signature)])
    }

    func testDifferentPortsGiveDifferentLabels() {
        let labels = Set((1...50).map { PortHosts.label(from: sign(PortHosts.subject(sandbox: sandbox, port: $0))) ?? "" })
        XCTAssertEqual(labels.count, 50)
    }

    /// The Root's stand-in for `SecretBox.signature`: something deterministic over the subject, as the real one is.
    private func sign(_ subject: String) -> String {
        SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func testTheSubjectNamesTheSandboxAndThePort() {
        XCTAssertEqual(PortHosts.subject(sandbox: sandbox, port: 8080), "abcdefghij0123456789:8080")
        XCTAssertNotEqual(PortHosts.subject(sandbox: sandbox, port: 8080), PortHosts.subject(sandbox: sandbox, port: 8081))
    }

    func testASignatureThatIsNotLowercaseHexGivesNoLabel() {
        XCTAssertNil(PortHosts.label(from: ""))
        XCTAssertNil(PortHosts.label(from: "abc"))
        XCTAssertNil(PortHosts.label(from: String(repeating: "z", count: 64)))
        XCTAssertNil(PortHosts.label(from: signature.uppercased()))
        XCTAssertNil(PortHosts.label(from: String(signature.prefix(19))))
    }

    func testOnlyALabelHostNamesAPort() throws {
        let label = try XCTUnwrap(PortHosts.label(from: signature))
        XCTAssertEqual(PortHosts.host(label: label, domain: "ruvio.site"), "\(label).ruvio.site")
        XCTAssertEqual(PortHosts.label(inHost: "\(label).ruvio.site", domain: "ruvio.site"), label)
        XCTAssertEqual(PortHosts.label(inHost: "\(label).ruvio.site:443", domain: "ruvio.site"), label)
        XCTAssertEqual(PortHosts.label(inHost: "\(label).RUVIO.SITE", domain: "ruvio.site"), label)
        XCTAssertNil(PortHosts.label(inHost: "ruvio.site", domain: "ruvio.site"))
        XCTAssertNil(PortHosts.label(inHost: "panel.ruvio.site", domain: "ruvio.site"))
        XCTAssertNil(PortHosts.label(inHost: "\(label).ruvio.site.evil.test", domain: "ruvio.site"))
        XCTAssertNil(PortHosts.label(inHost: "\(label)\(label).ruvio.site", domain: "ruvio.site"))
        XCTAssertNil(PortHosts.label(inHost: nil, domain: "ruvio.site"))
        XCTAssertNil(PortHosts.label(inHost: "\(label).sandbox.ruvio.site", domain: "ruvio.site"))
    }

    func testALabelWithACapitalOrTheWrongAlphabetIsNotOne() {
        XCTAssertFalse(PortHosts.isLabel("AAAAAAAAAAAAAAAA"))
        XCTAssertFalse(PortHosts.isLabel("aaaaaaaaaaaaaaa"))
        XCTAssertFalse(PortHosts.isLabel("aaaaaaaaaaaaaaaaa"))
        XCTAssertFalse(PortHosts.isLabel("1aaaaaaaaaaaaaaa"))
        XCTAssertFalse(PortHosts.isLabel("aaaaaaaaaaaaaaa8"))
    }
}
