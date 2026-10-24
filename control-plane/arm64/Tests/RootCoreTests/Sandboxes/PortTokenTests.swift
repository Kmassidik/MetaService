import CryptoKit
import Foundation
import XCTest
@testable import RootCore

/// The token that travels with a request to a port host: issued by the Root, checked before any helper call, short-lived.
final class PortTokenTests: XCTestCase {
    private let sandbox = "abcdefghij0123456789"
    private let label = "6dq5fq5uuwlio6dj"
    private let now = Date(timeIntervalSince1970: 1_792_800_000)

    /// The Root's stand-in for `SecretBox.signature`: a signature over the subject, as the real one is. A plain SHA-256 is
    /// enough here, because the rule under test is the shape and the comparison, not the key.
    private func sign(_ subject: String) -> String {
        SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func issue(port: Int = 8080, label: String? = nil) throws -> PortToken.Issued {
        let label = label ?? self.label
        let expiry = PortToken.expiry(now: now)
        let signature = sign(PortToken.subject(label: label, sandbox: sandbox, port: port, expiresAt: expiry))
        return try XCTUnwrap(PortToken.issue(sandbox: sandbox, port: port, label: label, now: now, lifetimeSignature: signature))
    }

    private func verify(_ token: String, label: String? = nil, at moment: Date? = nil) -> Result<PortToken.Claims, PortToken.Refusal> {
        PortToken.verify(token: token, label: label ?? self.label, now: moment ?? now, signature: sign)
    }

    // MARK: issuing and checking

    func testATokenIssuedForAHostProvesIt() throws {
        let issued = try issue()
        let claims = try verify(issued.token).get()
        XCTAssertEqual(claims.sandbox, sandbox)
        XCTAssertEqual(claims.port, 8080)
        XCTAssertEqual(claims.label, label)
        XCTAssertEqual(claims.expiresAt, PortToken.expiry(now: now))
        XCTAssertEqual(issued.expiresAt, claims.expiresAt)
        XCTAssertEqual(issued.expiresAt.timeIntervalSince(now), TimeInterval(PortToken.lifetimeSeconds))
        XCTAssertEqual(PortToken.lifetimeSeconds, 15 * 60)
    }

    func testATokenIsVersionedAndHoldsItsParts() throws {
        let token = try issue().token
        let fields = token.split(separator: ".").map(String.init)
        XCTAssertEqual(fields.count, 6)
        XCTAssertEqual(fields[0], PortToken.version)
        XCTAssertEqual(fields[1], label)
        XCTAssertEqual(fields[2], String(Int(PortToken.expiry(now: now).timeIntervalSince1970)))
        XCTAssertEqual(fields[3], sandbox)
        XCTAssertEqual(fields[4], "8080")
        XCTAssertEqual(fields[5].count, PortToken.macCharacters)
        XCTAssertLessThanOrEqual(token.count, PortToken.maxLength)
    }

    func testATokenStopsWorkingAtItsExpiry() throws {
        let issued = try issue()
        XCTAssertEqual(verify(issued.token, at: issued.expiresAt.addingTimeInterval(-1)), .success(try verify(issued.token).get()))
        XCTAssertEqual(verify(issued.token, at: issued.expiresAt), .failure(.expired))
        XCTAssertEqual(verify(issued.token, at: issued.expiresAt.addingTimeInterval(60)), .failure(.expired))
    }

    func testATokenForAnotherHostIsARefusalOfItsOwn() throws {
        let token = try issue().token
        XCTAssertEqual(verify(token, label: "aerukz4jvpg66ajd"), .failure(.wrongLabel))
    }

    func testAChangedTokenIsRefused() throws {
        let token = try issue().token
        var fields = token.split(separator: ".").map(String.init)
        fields[2] = String(Int(fields[2])! + 3600)
        XCTAssertEqual(verify(fields.joined(separator: ".")), .failure(.malformed))
        fields = token.split(separator: ".").map(String.init)
        fields[4] = "8081"
        XCTAssertEqual(verify(fields.joined(separator: ".")), .failure(.malformed))
        fields = token.split(separator: ".").map(String.init)
        fields[5] = String(repeating: "0", count: PortToken.macCharacters)
        XCTAssertEqual(verify(fields.joined(separator: ".")), .failure(.malformed))
    }

    func testATokenThatIsNotOursIsMalformed() throws {
        XCTAssertEqual(verify(""), .failure(.malformed))
        XCTAssertEqual(verify("v2.\(label).1.\(sandbox).8080." + String(repeating: "a", count: 32)), .failure(.malformed))
        XCTAssertEqual(verify("v1.\(label).later.\(sandbox).8080." + String(repeating: "a", count: 32)), .failure(.malformed))
        XCTAssertEqual(verify("v1.\(label).1.\(sandbox).0." + String(repeating: "a", count: 32)), .failure(.malformed))
        XCTAssertEqual(verify("v1.\(label).1.\(sandbox).70000." + String(repeating: "a", count: 32)), .failure(.malformed))
        XCTAssertEqual(verify("v1.\(label).1.\(sandbox).8080"), .failure(.malformed))
        XCTAssertEqual(verify(String(repeating: "a", count: PortToken.maxLength + 1)), .failure(.malformed))
    }

    func testTheSignatureMustBeForThisTokensExactClaims() throws {
        let issued = try issue()
        let other = sign("something else")
        XCTAssertEqual(PortToken.verify(token: issued.token, label: label, now: now, signature: { _ in other }), .failure(.malformed))
    }

    func testATokenCannotBeIssuedFromPartsThatAreNotOurs() {
        let signature = sign("whatever")
        XCTAssertNil(PortToken.issue(sandbox: sandbox, port: 0, label: label, now: now, lifetimeSignature: signature))
        XCTAssertNil(PortToken.issue(sandbox: sandbox, port: 65536, label: label, now: now, lifetimeSignature: signature))
        XCTAssertNil(PortToken.issue(sandbox: sandbox, port: 8080, label: "AERUKZ4JVPG66AJD", now: now, lifetimeSignature: signature))
        XCTAssertNil(PortToken.issue(sandbox: sandbox, port: 8080, label: label, now: now, lifetimeSignature: "abcdef"))
        XCTAssertNil(PortToken.issue(sandbox: "", port: 8080, label: label, now: now, lifetimeSignature: signature))
    }

    // MARK: where it travels

    func testTheTokenTravelsInTheQueryOrTheHeader() {
        XCTAssertEqual(PortToken.presented(query: "a=1&token=abc123", header: nil), "abc123")
        XCTAssertEqual(PortToken.presented(query: "token=abc123&a=1", header: nil), "abc123")
        XCTAssertEqual(PortToken.presented(query: nil, header: "abc123"), "abc123")
        XCTAssertEqual(PortToken.presented(query: "a=1", header: "abc123"), "abc123")
        XCTAssertEqual(PortToken.presented(query: "token=abc123", header: "abc123"), "abc123")
        XCTAssertEqual(PortToken.queryName, "token")
        XCTAssertEqual(PortToken.headerName, "X-Port-Token")
    }

    func testARequestWithoutOneTokenIsRefused() {
        XCTAssertNil(PortToken.presented(query: nil, header: nil))
        XCTAssertNil(PortToken.presented(query: "", header: ""))
        XCTAssertNil(PortToken.presented(query: "a=1", header: nil))
        XCTAssertNil(PortToken.presented(query: "token=", header: nil))
        XCTAssertNil(PortToken.presented(query: "token", header: nil))
        XCTAssertNil(PortToken.presented(query: "token=abc", header: "def"))
    }
}
