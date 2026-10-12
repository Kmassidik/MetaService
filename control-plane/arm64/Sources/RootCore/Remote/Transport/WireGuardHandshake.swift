import Foundation

/// Reads the output of `wg show <interface> latest-handshakes` (one line per peer: public key, tab, unix time, 0 when there has been none).
/// A machine is "connected" when its last handshake is recent: WireGuard renews it about every two minutes while traffic flows.
public enum WireGuardHandshake {
    public static let freshSeconds: TimeInterval = 180

    public static func parse(_ output: String) -> [String: Date] {
        var times: [String: Date] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard parts.count == 2, let seconds = TimeInterval(parts[1]), seconds > 0 else { continue }
            times[String(parts[0])] = Date(timeIntervalSince1970: seconds)
        }
        return times
    }

    public static func state(of publicKey: String, handshakes: [String: Date], now: Date) -> TransportState {
        guard let last = handshakes[publicKey] else { return .offline(reason: "no handshake yet") }
        guard now.timeIntervalSince(last) <= freshSeconds else { return .offline(reason: "last handshake too old") }
        return .connected(since: last)
    }
}
