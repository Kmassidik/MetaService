import XCTest
@testable import MSCore

final class SharedRulesTests: XCTestCase {
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

    private func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    func testStrictObjectTellsBoolFromNumber() throws {
        let object = try StrictObject(data: data(["flag": true, "count": 1]), allowed: ["flag", "count"])
        XCTAssertNoThrow(try object.bool("flag"))
        XCTAssertThrowsError(try object.bool("count"))
        XCTAssertThrowsError(try object.int("flag", range: 0...5))
        XCTAssertEqual(try object.int("count", range: 0...5), 1)
        XCTAssertThrowsError(try object.int("count", range: 2...5))
    }
}
