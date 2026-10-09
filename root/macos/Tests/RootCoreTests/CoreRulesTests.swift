import XCTest
@testable import RootCore

final class CoreRulesTests: XCTestCase {
    func testMachineStateBoundaries() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(MachineStates.derive(lastSeen: nil, now: now, workloadStates: []), .offline)
        XCTAssertEqual(MachineStates.derive(lastSeen: now.addingTimeInterval(-44), now: now, workloadStates: []), .online)
        XCTAssertEqual(MachineStates.derive(lastSeen: now.addingTimeInterval(-45), now: now, workloadStates: []), .online)
        XCTAssertEqual(MachineStates.derive(lastSeen: now.addingTimeInterval(-46), now: now, workloadStates: []), .offline)
        XCTAssertEqual(MachineStates.derive(lastSeen: now, now: now, workloadStates: ["running", "provisioning"]), .busy)
        XCTAssertEqual(MachineStates.derive(lastSeen: now, now: now, workloadStates: ["running", "stopped"]), .online)
    }

    func testPasswordHashMatchesTheRfc7914Vector() {
        // PBKDF2-HMAC-SHA256, P = "passwd", S = "salt", c = 1 (RFC 7914 section 11): the first 32 bytes of the derived key.
        let key = PasswordHash.derive(password: "passwd", salt: Data("salt".utf8), iterations: 1)
        XCTAssertEqual(key.map { String(format: "%02x", $0) }.joined(), "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc")
    }

    func testOnlyTheRightPasswordMatchesAndSaltsDiffer() {
        let salt = PasswordHash.randomSalt(), other = PasswordHash.randomSalt()
        XCTAssertNotEqual(salt, other)
        let hash = PasswordHash.derive(password: "right one", salt: salt, iterations: 1000)
        XCTAssertTrue(PasswordHash.matches(password: "right one", salt: salt, iterations: 1000, expected: hash))
        for wrong in ["wrong one", "right one ", "", "Right one"] { XCTAssertFalse(PasswordHash.matches(password: wrong, salt: salt, iterations: 1000, expected: hash), wrong) }
        XCTAssertFalse(PasswordHash.matches(password: "right one", salt: other, iterations: 1000, expected: hash))
    }

    func testCookiesRefuseRepeats() {
        XCTAssertEqual(Cookies.value(named: "s", header: "a=1; s=xyz; b=2"), "xyz")
        XCTAssertNil(Cookies.value(named: "s", header: "s=one; s=two"))
        XCTAssertNil(Cookies.value(named: "s", header: nil))
        XCTAssertNil(Cookies.value(named: "s", header: "other=1"))
    }

    func testCookieFlags() {
        let line = Cookies.set(name: "n", value: "v", maxAge: 60, secure: true, sameSite: "Strict")
        for part in ["HttpOnly", "Secure", "SameSite=Strict", "Path=/", "Max-Age=60"] { XCTAssertTrue(line.contains(part), part) }
        XCTAssertFalse(Cookies.set(name: "n", value: "v", maxAge: 60, secure: false, sameSite: "Lax").contains("Secure"))
    }

    func testLoopbackAddressesStayOnThisMachine() {
        for good in ["127.0.0.1", "127.1.2.3", "localhost", "::1"] { XCTAssertTrue(OperatorGate.isLoopback(good), good) }
        for bad in ["0.0.0.0", "192.168.100.40", "10.0.0.1", "8.8.8.8", "", "127.0.0", "127.0.0.1.evil.com", "example.com", "::"] { XCTAssertFalse(OperatorGate.isLoopback(bad), bad) }
    }

    func testTheHostHeaderMustBeThePublicHostExactly() {
        let url = "http://localhost:9100"
        XCTAssertTrue(OperatorGate.hostMatches(header: "localhost:9100", publicURL: url))
        XCTAssertTrue(OperatorGate.hostMatches(header: "LOCALHOST:9100", publicURL: url))
        for bad: String? in [nil, "", "evil.example", "evil.example:9100", "localhost", "localhost:9101", "localhost:9100.evil.com", "127.0.0.1:9100", "localhost:9100 "] {
            XCTAssertFalse(OperatorGate.hostMatches(header: bad, publicURL: url), bad ?? "nil")
        }
        XCTAssertTrue(OperatorGate.hostMatches(header: "panel.example.com", publicURL: "https://panel.example.com"))
        XCTAssertFalse(OperatorGate.hostMatches(header: "panel.example.com:443", publicURL: "https://panel.example.com"))
    }

    func testOriginIsExact() {
        let expected = "http://localhost:9100"
        XCTAssertTrue(Origin.matches(header: "http://localhost:9100", expected: expected))
        XCTAssertTrue(Origin.matches(header: "HTTP://LocalHost:9100", expected: expected))
        for bad in [nil, "", "null", "http://localhost:9101", "http://localhost:9100.evil.com", "http://localhost", "https://localhost:9100",
                    "http://evil.com", "http://localhost:9100/path"] {
            XCTAssertFalse(Origin.matches(header: bad, expected: expected), bad ?? "nil")
        }
    }
}
