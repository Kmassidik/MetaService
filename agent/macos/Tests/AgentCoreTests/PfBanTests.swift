import XCTest
import AgentCore

/// A thread-safe recorder the PfBan run closure can capture without inout.
final class CallsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    private let source: UnsafeMutablePointer<[String]>
    private(set) var hasBanned = false

    init(_ source: UnsafeMutablePointer<[String]>) { self.source = source }
    func append(_ item: String) {
        lock.lock(); items.append(item)
        if item.contains("-T add") { hasBanned = true }
        lock.unlock()
        source.pointee = items
    }
}

/// The ban rules: threshold, window, expiry, loopback immunity, and the pf call content.
final class PfBanTests: XCTestCase {
    private func make(now: @escaping @Sendable () -> Int, calls: CallsRecorder) -> PfBan {
        PfBan(run: { tool, args, _ in
            let joined = tool + " " + args.joined(separator: " ")
            calls.append(joined)
            if joined.contains("-T test") { return calls.hasBanned ? "1/1 addresses match." : "0/1 addresses match." }
            return "1/1 addresses added."
        }, now: now)
    }

    func testThreeFailuresWithinWindowBanOnce() async throws {
        var calls: [String] = []
        var t = 1_000
        let now = { t }
        var ban = make(now: now, calls: CallsRecorder(&calls))
        var blocked: SecurityEvent?
        for _ in 0..<3 {
            blocked = await ban.failed(address: "1.2.3.4")
            if blocked != nil { break }
            t += 60
        }
        // the third failure bans: the event carries address and the failure count
        let event = try XCTUnwrap(blocked, "third failure must ban")
        XCTAssertEqual(event.type, .blocked)
        XCTAssertEqual(event.address, "1.2.3.4")
        XCTAssertEqual(event.count, 3)
        XCTAssertTrue(calls.contains { $0.contains("-T add 1.2.3.4") })
        // a fourth failure while banned is silent
        let again = await ban.failed(address: "1.2.3.4")
        XCTAssertNil(again)
    }

    func testTwoFailuresNeverBan() async throws {
        var calls: [String] = []
        var t = 1_000
        let now = { t }
        var ban = make(now: now, calls: CallsRecorder(&calls))
        let one = await ban.failed(address: "2.2.2.2")
        t += 60
        let two = await ban.failed(address: "2.2.2.2")
        XCTAssertNil(one)
        XCTAssertNil(two)
        XCTAssertFalse(calls.contains { $0.contains("-T add") })
    }

    func testFailuresOutsideWindowDoNotStack() async throws {
        var calls: [String] = []
        var t = 1_000
        let now = { t }
        var ban = make(now: now, calls: CallsRecorder(&calls))
        let a = await ban.failed(address: "3.3.3.3")
        t += 3600 // window is 600s: this failure does not stack with the first
        let b = await ban.failed(address: "3.3.3.3")
        XCTAssertNil(a)
        XCTAssertNil(b)
        XCTAssertFalse(calls.contains { $0.contains("-T add") })
    }

    func testLoopbackAndPrivateAddressesAreImmune() async throws {
        var calls: [String] = []
        let now = { 1_000 }
        var ban = make(now: now, calls: CallsRecorder(&calls))
        for address in ["127.0.0.1", "10.0.0.5", "192.168.0.30"] {
            for _ in 0..<5 {
                let event = await ban.failed(address: address)
                XCTAssertNil(event, "\(address) must never be banned")
            }
        }
        XCTAssertFalse(calls.contains { $0.contains("-T add") })
    }
}
