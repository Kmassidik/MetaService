import XCTest
import AgentCore
final class MiniDebug: XCTestCase {
    func testParseFakeLine() {
        let zone = TimeZone(identifier: "Asia/Jakarta")!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = zone
        let epoch = 1_700_000_000
        let line = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch))) + ".000 E  sshd-session[111:a1] Invalid user u11 from 10.0.0.11 port 5"
        print("LINE:", line)
        let seen = SshVerboseLog.parse(line, zone: zone)
        print("SEEN:", seen)
        XCTAssertEqual(seen.count, 1)
    }
}
