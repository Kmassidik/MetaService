import Darwin
import Foundation

/// `log show --style compact` timestamps: `2026-11-01 14:23:06` in the machine's own zone, to Unix seconds.
enum SecurityLogTime {
    static func isoNow(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static let shape = Array("0000-00-00 00:00:00".utf8)

    static func epoch(of text: String, zone: TimeZone) -> Int? {
        let bytes = Array(text.utf8)
        guard bytes.count == shape.count else { return nil }
        var digits: [Int] = []
        for (index, slot) in shape.enumerated() {
            let isDigit = slot == UInt8(ascii: "0")
            guard isDigit ? (bytes[index] >= 48 && bytes[index] <= 57) : bytes[index] == slot else { return nil }
            if isDigit { digits.append(Int(bytes[index]) - 48) }
        }
        return epoch(digits: digits, zone: zone)
    }

    private static func epoch(digits d: [Int], zone: TimeZone) -> Int? {
        var parts = tm()
        parts.tm_year = Int32(d[0] * 1000 + d[1] * 100 + d[2] * 10 + d[3] - 1900)
        parts.tm_mon = Int32(d[4] * 10 + d[5] - 1)
        parts.tm_mday = Int32(d[6] * 10 + d[7])
        parts.tm_hour = Int32(d[8] * 10 + d[9])
        parts.tm_min = Int32(d[10] * 10 + d[11])
        parts.tm_sec = Int32(d[12] * 10 + d[13])
        guard (0...11).contains(parts.tm_mon), (1...31).contains(parts.tm_mday), parts.tm_hour < 24, parts.tm_min < 60, parts.tm_sec <= 60 else { return nil }
        let asIfUtc = Int(timegm(&parts))
        return asIfUtc - zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(asIfUtc)))
    }
}
