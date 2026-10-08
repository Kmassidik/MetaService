import XCTest
@testable import RootCore

final class CoreRulesTests: XCTestCase {
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
