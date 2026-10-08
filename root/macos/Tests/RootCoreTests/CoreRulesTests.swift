import XCTest
@testable import RootCore

final class CoreRulesTests: XCTestCase {
    func testIdsAcceptOnlyTheContractShape() {
        for good in ["a", "mac-mini", "dgx-spark-1", "0abc", String(repeating: "a", count: 63)] { XCTAssertTrue(Ids.isValid(good), good) }
        let bad = ["", "UPPER", "has space", "semi;colon", "$(reboot)", "`id`", "a/b", "../etc", "-lead", "x'; DROP TABLE machines;--",
                   "<script>", String(repeating: "a", count: 64), "line\nbreak", "tab\t"]
        for item in bad { XCTAssertFalse(Ids.isValid(item), item) }
    }

    func testSemver() {
        XCTAssertTrue(Ids.isSemver("1.2.3"))
        for bad in ["1.2", "v1.2.3", "1.2.3; reboot", "1.2.3.4", ""] { XCTAssertFalse(Ids.isSemver(bad), bad) }
    }

    func testRandomTokensAreLongAndDifferent() {
        let first = Tokens.random(), second = Tokens.random()
        XCTAssertNotEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.count, 43)
        XCTAssertNil(first.firstIndex(where: { "+/=".contains($0) }))
    }

    func testSha256KnownVector() {
        XCTAssertEqual(Tokens.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testConstantTimeEqual() {
        XCTAssertTrue(Tokens.constantTimeEqual("abc", "abc"))
        XCTAssertFalse(Tokens.constantTimeEqual("abc", "abd"))
        XCTAssertFalse(Tokens.constantTimeEqual("abc", "abcd"))
        XCTAssertFalse(Tokens.constantTimeEqual("", "a"))
    }

    func testPkceMatchesRfc7636Example() {
        XCTAssertEqual(Pkce.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testMachineStateBoundaries() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(MachineStates.derive(lastSeen: nil, now: now, workloadStates: []), .offline)
        XCTAssertEqual(MachineStates.derive(lastSeen: now.addingTimeInterval(-44), now: now, workloadStates: []), .online)
        XCTAssertEqual(MachineStates.derive(lastSeen: now.addingTimeInterval(-45), now: now, workloadStates: []), .online)
        XCTAssertEqual(MachineStates.derive(lastSeen: now.addingTimeInterval(-46), now: now, workloadStates: []), .offline)
        XCTAssertEqual(MachineStates.derive(lastSeen: now, now: now, workloadStates: ["running", "provisioning"]), .busy)
        XCTAssertEqual(MachineStates.derive(lastSeen: now, now: now, workloadStates: ["running", "stopped"]), .online)
    }

    func testThrottleLimitsThenRecovers() {
        let clock = FixedClock()
        let throttle = Throttle(clock: clock)
        for _ in 0..<3 { XCTAssertTrue(throttle.allow("ip", limit: 3, seconds: 60)) }
        XCTAssertFalse(throttle.allow("ip", limit: 3, seconds: 60))
        XCTAssertTrue(throttle.allow("other", limit: 3, seconds: 60))
        clock.advance(61)
        XCTAssertTrue(throttle.allow("ip", limit: 3, seconds: 60))
    }

    func testIsFullDoesNotCount() {
        let throttle = Throttle(clock: FixedClock())
        XCTAssertFalse(throttle.isFull("k", limit: 2))
        XCTAssertTrue(throttle.allow("k", limit: 2, seconds: 60))
        XCTAssertFalse(throttle.isFull("k", limit: 2))
        XCTAssertTrue(throttle.allow("k", limit: 2, seconds: 60))
        XCTAssertTrue(throttle.isFull("k", limit: 2))
        XCTAssertTrue(throttle.isFull("k", limit: 2), "asking again changes nothing")
    }

    func testThrottleRefusesWhenFull() {
        let throttle = Throttle(clock: FixedClock(), maxKeys: 2)
        XCTAssertTrue(throttle.allow("a", limit: 5, seconds: 60))
        XCTAssertTrue(throttle.allow("b", limit: 5, seconds: 60))
        XCTAssertFalse(throttle.allow("c", limit: 5, seconds: 60))
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
