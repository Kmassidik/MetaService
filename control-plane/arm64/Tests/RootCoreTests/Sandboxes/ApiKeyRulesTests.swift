import Foundation
import XCTest
@testable import RootCore

final class ApiKeyRulesTests: XCTestCase {
    private let secret = String(repeating: "a", count: 43)
    private let otherSecret = String(repeating: "b", count: 43)

    private func stored(prefix: String, secret: String, revokedAt: Date? = nil) -> StoredApiKey {
        StoredApiKey(id: "key-1", team: "team-1", prefix: prefix, secretHash: ApiKeyRules.hash(secret: secret), revokedAt: revokedAt)
    }

    func testAnIssuedKeyIsAMarkerAPrefixAndTheSecret() throws {
        let issued = ApiKeyRules.issue()
        let parts = try XCTUnwrap(ApiKeyRules.parse(issued.key))
        XCTAssertTrue(issued.prefix.hasPrefix("msb_"))
        XCTAssertEqual(issued.prefix.count, ApiKeyRules.marker.count + 1 + ApiKeyRules.prefixCharacters)
        XCTAssertEqual(parts.prefix, issued.prefix)
        XCTAssertEqual(parts.secret, String(issued.key.dropFirst(issued.prefix.count + 1)))
        XCTAssertEqual(parts.secret.count, ApiKeyRules.secretCharacters)
        XCTAssertEqual(issued.secretHash, ApiKeyRules.hash(secret: parts.secret))
        XCTAssertEqual(issued.secretHash.count, ApiKeyRules.hashHexCharacters)
    }

    func testTwoIssuedKeysNeverShareAPrefix() {
        let keys = Set((0..<20).map { _ in ApiKeyRules.issue().prefix })
        XCTAssertEqual(keys.count, 20)
    }

    func testAKeyWithPunctuationInItsSecretStillParses() throws {
        let key = ApiKeyRules.text(prefix: "msb_ab12cd34", secret: String(repeating: "-_", count: 21) + "x")
        let parts = try XCTUnwrap(ApiKeyRules.parse(key))
        XCTAssertEqual(parts.prefix, "msb_ab12cd34")
        XCTAssertEqual(parts.secret.count, ApiKeyRules.secretCharacters)
    }

    func testKeysThatAreNotOursAreRefused() {
        let good = ApiKeyRules.issue(secret: secret).key
        XCTAssertNil(ApiKeyRules.parse(""))
        XCTAssertNil(ApiKeyRules.parse("e2b_" + String(good.dropFirst(4))))
        XCTAssertNil(ApiKeyRules.parse(good + "x"))
        XCTAssertNil(ApiKeyRules.parse(String(good.dropLast())))
        XCTAssertNil(ApiKeyRules.parse(" \(good)"))
        XCTAssertNil(ApiKeyRules.parse(good + "\n"))
        XCTAssertNil(ApiKeyRules.parse("msb_AB12CD34_" + secret))
        XCTAssertNil(ApiKeyRules.parse("msb_ab12cd34 " + secret))
    }

    func testTheHashIsDeterministicHex() {
        XCTAssertEqual(ApiKeyRules.hash(secret: secret), ApiKeyRules.hash(secret: secret))
        XCTAssertNotEqual(ApiKeyRules.hash(secret: secret), ApiKeyRules.hash(secret: otherSecret))
        XCTAssertTrue(ApiKeyRules.hash(secret: secret).allSatisfy(\.isHexDigit))
        XCTAssertEqual(ApiKeyRules.hash(secret: secret), Tokens.sha256Hex(secret))
    }

    func testAGoodKeyIsAccepted() throws {
        let issued = ApiKeyRules.issue(secret: secret)
        let key = stored(prefix: issued.prefix, secret: secret)
        XCTAssertEqual(ApiKeyGate.check(issued.key, lookup: { _ in key }), .accepted(key))
    }

    func testAWrongSecretWithTheRightPrefixIsUnknown() throws {
        let issued = ApiKeyRules.issue(secret: secret)
        let key = stored(prefix: issued.prefix, secret: secret)
        let wrong = ApiKeyRules.text(prefix: issued.prefix, secret: otherSecret)
        XCTAssertEqual(ApiKeyGate.check(wrong, lookup: { _ in key }), .unknown)
    }

    func testAnUnknownPrefixIsUnknown() throws {
        let issued = ApiKeyRules.issue(secret: secret)
        XCTAssertEqual(ApiKeyGate.check(issued.key, lookup: { _ in nil }), .unknown)
    }

    func testARevokedKeyIsRefusedBeforeItsSecretIsChecked() throws {
        let issued = ApiKeyRules.issue(secret: secret)
        let revoked = stored(prefix: issued.prefix, secret: secret, revokedAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(ApiKeyGate.check(issued.key, lookup: { _ in revoked }), .revoked)
        XCTAssertEqual(ApiKeyGate.check(issued.key, lookup: { _ in revoked }).refusal, .revoked)
    }

    func testAKeyThatIsNotShapedRightNeverReachesTheStore() {
        var lookups = 0
        XCTAssertEqual(ApiKeyGate.check("not-a-key", lookup: { _ in lookups += 1; return nil }), .unknown)
        XCTAssertEqual(lookups, 0)
    }

    func testTheRefusalsSayWhy() {
        XCTAssertEqual(ApiKeyCheck.unknown.refusal?.code, "invalid_key")
        XCTAssertEqual(ApiKeyCheck.revoked.refusal?.code, "revoked_key")
        XCTAssertNil(ApiKeyCheck.accepted(stored(prefix: "msb_ab12cd34", secret: secret)).refusal)
    }
}
