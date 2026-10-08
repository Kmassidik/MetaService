import XCTest
@testable import RootCore

final class IdTokenClaimsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let client = "client-123.apps.googleusercontent.com"

    private func claims(_ change: ((inout [String: Any]) -> Void)? = nil) -> [String: Any] {
        var value: [String: Any] = ["sub": "1010", "aud": client, "iss": "https://accounts.google.com", "exp": now.timeIntervalSince1970 + 600,
                                    "nonce": "n-1", "email_verified": true, "email": "Kurnia@Example.com"]
        change?(&value)
        return value
    }

    private func verified(_ change: ((inout [String: Any]) -> Void)? = nil) -> [String: Any] {
        var value: [String: Any] = ["sub": "1010", "aud": client]
        change?(&value)
        return value
    }

    private func check(claims c: [String: Any], verified v: [String: Any]? = nil, nonce: String = "n-1") throws -> VerifiedIdentity {
        try IdTokenClaims.identity(claims: c, verified: v ?? verified(), clientId: client, nonce: nonce, now: now)
    }

    func testGoodTokenGivesALowercaseEmail() throws {
        XCTAssertEqual(try check(claims: claims()), VerifiedIdentity(subject: "1010", email: "kurnia@example.com"))
    }

    func testEachWrongClaimIsRefused() {
        let cases: [(String, [String: Any], [String: Any]?, String)] = [
            ("wrong audience", claims { $0["aud"] = "other" }, nil, "n-1"),
            ("verified audience differs", claims(), verified { $0["aud"] = "other" }, "n-1"),
            ("wrong issuer", claims { $0["iss"] = "https://evil.example" }, nil, "n-1"),
            ("expired", claims { $0["exp"] = 1_700_000_000.0 }, nil, "n-1"),
            ("no expiry", claims { $0["exp"] = nil }, nil, "n-1"),
            ("wrong nonce", claims(), nil, "other"),
            ("no nonce", claims { $0["nonce"] = nil }, nil, "n-1"),
            ("subject differs from Google's check", claims(), verified { $0["sub"] = "9999" }, "n-1"),
            ("no subject", claims { $0["sub"] = nil }, nil, "n-1"),
            ("subject too long", claims { $0["sub"] = String(repeating: "1", count: 256) }, verified { $0["sub"] = String(repeating: "1", count: 256) }, "n-1"),
        ]
        for (label, c, v, nonce) in cases {
            XCTAssertThrowsError(try check(claims: c, verified: v, nonce: nonce), label) { XCTAssertEqual($0 as? ClaimsFailure, .invalid, label) }
        }
    }

    func testUnverifiedOrMissingEmailIsRefusedSeparately() {
        for change: (inout [String: Any]) -> Void in [{ $0["email_verified"] = false }, { $0["email_verified"] = "true" }, { $0["email"] = nil }, { $0["email"] = "" }] {
            XCTAssertThrowsError(try check(claims: claims(change))) { XCTAssertEqual($0 as? ClaimsFailure, .emailNotVerified) }
        }
    }

    func testDecodeReadsThePayloadAndRefusesJunk() throws {
        let payload = try JSONSerialization.data(withJSONObject: ["sub": "1"])
        let token = "e30." + Tokens.base64url(payload) + ".sig"
        XCTAssertEqual(try IdTokenClaims.decode(token)["sub"] as? String, "1")
        for junk in ["", "a.b", "a.b.c.d", "a.!!!.c", "a." + Tokens.base64url(Data("[1]".utf8)) + ".c"] {
            XCTAssertThrowsError(try IdTokenClaims.decode(junk), junk)
        }
    }
}
