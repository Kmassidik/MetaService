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

final class SecretBoxTests: XCTestCase {
    private func path() -> String { NSTemporaryDirectory() + "ms-key-\(UUID().uuidString)" }

    func testSealAndOpenRoundTripWithFreshNonces() throws {
        let box = try SecretBox.loadOrCreate(path: path())
        let first = try box.seal("machine-secret"), second = try box.seal("machine-secret")
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.contains("machine-secret"))
        XCTAssertEqual(try box.open(first), "machine-secret")
    }

    func testTamperedOrForeignDataDoesNotOpen() throws {
        let box = try SecretBox.loadOrCreate(path: path()), other = try SecretBox.loadOrCreate(path: path())
        let sealed = try box.seal("x")
        XCTAssertThrowsError(try other.open(sealed))
        XCTAssertThrowsError(try box.open(String(sealed.dropLast(2)) + "AA"))
        for junk in ["", "not base64 !!", "AAAA"] { XCTAssertThrowsError(try box.open(junk), junk) }
    }

    func testTheKeyFileIsCreatedPrivateAndReused() throws {
        let file = path()
        let first = try SecretBox.loadOrCreate(path: file)
        XCTAssertEqual(((try FileManager.default.attributesOfItem(atPath: file))[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try SecretBox.loadOrCreate(path: file).open(try first.seal("again")), "again")
    }

    func testALooseOrBrokenKeyFileIsRefused() throws {
        let file = path()
        _ = try SecretBox.loadOrCreate(path: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file)
        XCTAssertThrowsError(try SecretBox.loadOrCreate(path: file)) { XCTAssertEqual($0 as? SecretBoxError, .looseKeyFile) }
        let broken = path()
        FileManager.default.createFile(atPath: broken, contents: Data("short".utf8), attributes: [.posixPermissions: 0o600])
        XCTAssertThrowsError(try SecretBox.loadOrCreate(path: broken)) { XCTAssertEqual($0 as? SecretBoxError, .badKeyFile) }
    }
}
