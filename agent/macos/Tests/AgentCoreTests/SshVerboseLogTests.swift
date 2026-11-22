import XCTest
import AgentCore

/// The VERBOSE sshd parser against the line shapes macOS really prints (docs/security-model.md §5).
final class SshVerboseLogTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Jakarta")!
    private let prefix = "2026-11-22 13:04:09.770 E  sshd-session[2164:13cf356] "

    private func lines(_ messages: [String]) -> [VerboseSighting] {
        SshVerboseLog.parse(messages.map { prefix + $0 }.joined(separator: "\n"), zone: zone)
    }

    func testFailedPasswordForInvalidUserCarriesUserAndAddress() {
        let seen = lines(["Failed password for invalid user admin from 1.2.3.4 port 51000 ssh2"])
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.user, "admin")
        XCTAssertEqual(seen.first?.address, "1.2.3.4")
        XCTAssertEqual(seen.first?.failed, true)
    }

    func testFailedPasswordForRealUser() {
        let seen = lines(["Failed password for root from 5.6.7.8 port 51001 ssh2"])
        XCTAssertEqual(seen.first?.user, "root")
        XCTAssertEqual(seen.first?.address, "5.6.7.8")
        XCTAssertEqual(seen.first?.failed, true)
    }

    func testInvalidUserWithoutPort() {
        let seen = lines(["Invalid user oracle from 9.9.9.9"])
        XCTAssertEqual(seen.first?.user, "oracle")
        XCTAssertEqual(seen.first?.address, "9.9.9.9")
        XCTAssertEqual(seen.first?.failed, true)
    }

    func testAcceptedPublickeyIsALoginNotAFailure() {
        let seen = lines(["Accepted publickey for luca from 10.0.0.2 port 51002 ssh2: RSA SHA256:abc"])
        XCTAssertEqual(seen.first?.user, "luca")
        XCTAssertEqual(seen.first?.address, "10.0.0.2")
        XCTAssertEqual(seen.first?.failed, false)
        XCTAssertEqual(seen.first?.method, "publickey")
    }

    func testPreauthCloseCountsAsAFailure() {
        let seen = lines(["Connection closed by invalid user admin 1.2.3.4 port 51003 [preauth]"])
        XCTAssertEqual(seen.first?.failed, true)
        XCTAssertEqual(seen.first?.address, "1.2.3.4")
    }

    func testNoiseLinesAreSkipped() {
        let seen = SshVerboseLog.parse([
            "Timestamp               Ty Process[PID:TID]",
            prefix + "[com.apple.network.libinfo:si_destination_compare] send failed: Invalid argument",
            prefix + "(libsystem_info.dylib) Retrieve User by Name",
        ].joined(separator: "\n"), zone: zone)
        XCTAssertEqual(seen, [])
    }

    func testTimestampIsParsedInTheGivenZone() {
        let seen = lines(["Invalid user x from 1.1.1.1"])
        // 2026-11-22 13:04:09 WIB = 06:04:09Z
        XCTAssertEqual(seen.first?.epoch, Int("2026-11-22T06:04:09Z".dropLast(1).split(separator: "").count == 0 ? 0 : unixTime("2026-11-22T06:04:09Z")))
    }

    private func unixTime(_ iso: String) -> Int {
        var formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return Int(formatter.date(from: iso)!.timeIntervalSince1970)
    }
}
