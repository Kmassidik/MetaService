import Darwin
import Foundation

/// One line of `log show --style compact` that belongs to a `sshd-session` process: when, and which process id.
public struct SshSighting: Equatable {
    public let epoch: Int
    public let pid: Int
    public init(epoch: Int, pid: Int) { self.epoch = epoch; self.pid = pid }
}

/// Reads the compact log text. Modern macOS logs no user name or address for SSH; the only per-connection signal is that a `sshd-session`
/// process runs for it, so that is all this reads. Only fixed fields are taken from a line; the message text is never kept.
public enum SshConnectionLog {
    public static let processName = "sshd-session"
    /// `log show` prints times as `2026-11-01 14:23:06.234` in the machine's own zone.
    private static let timeLength = 19
    private static let dateTimeShape = Array("0000-00-00 00:00:00".utf8)

    /// Lines that are not a timestamped `sshd-session[pid:tid]` line (the header, the filter notice, other processes, noise) are skipped.
    public static func parse(_ text: String, zone: TimeZone) -> [SshSighting] {
        var sightings: [SshSighting] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let sighting = sighting(of: line, zone: zone) else { continue }
            sightings.append(sighting)
        }
        return sightings
    }

    private static func sighting(of line: Substring, zone: TimeZone) -> SshSighting? {
        guard let epoch = epoch(of: line, zone: zone) else { return nil }
        let rest = line.dropFirst(timeLength)
        guard let pid = pid(in: rest) else { return nil }
        return SshSighting(epoch: epoch, pid: pid)
    }

    /// The process column is `sshd-session[<pid>:<thread hex>]`, the first word that starts with the process name.
    private static func pid(in rest: Substring) -> Int? {
        let marker = processName + "["
        for word in rest.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true).prefix(4) where word.hasPrefix(marker) {
            let inside = word.dropFirst(marker.count).prefix { $0 != ":" && $0 != "]" }
            return inside.isEmpty ? nil : Int(inside)
        }
        return nil
    }

    private static func epoch(of line: Substring, zone: TimeZone) -> Int? {
        let bytes = Array(line.utf8.prefix(timeLength))
        guard bytes.count == timeLength else { return nil }
        var digits: [Int] = []
        for (index, shape) in dateTimeShape.enumerated() {
            let isSlot = shape == UInt8(ascii: "0")
            guard isSlot ? (bytes[index] >= 48 && bytes[index] <= 57) : bytes[index] == shape else { return nil }
            if isSlot { digits.append(Int(bytes[index]) - 48) }
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

/// How many connections happened in each hour.
public struct ConnectionHour: Equatable {
    /// Unix second of the start of the hour.
    public let hourStart: Int
    public let connections: Int
    /// The time of the last connection counted in this hour.
    public let lastEpoch: Int
}

/// Which process ids have already been counted, in log time. A `sshd-session` process id seen again within `memorySeconds` is the same connection
/// (a long session logs again when it ends), not a new one.
public struct ConnectionCounter: Equatable {
    public static let secondsPerHour = 3600
    /// A day: macOS hands out process ids in turn, and at hundreds of connections an hour it takes far longer than that to reuse one.
    public static let memorySeconds = 24 * 3600

    private var lastSeen: [Int: Int] = [:]

    public init() {}

    /// Counts the sightings (any order) and returns one entry per hour that had a new connection, oldest first. The counter remembers them.
    public mutating func count(_ sightings: [SshSighting]) -> [ConnectionHour] {
        var perHour: [Int: (connections: Int, last: Int)] = [:]
        for sighting in sightings.sorted(by: { $0.epoch < $1.epoch }) {
            let isNew = lastSeen[sighting.pid].map { sighting.epoch - $0 > Self.memorySeconds } ?? true
            lastSeen[sighting.pid] = sighting.epoch
            guard isNew else { continue }
            let hour = sighting.epoch - sighting.epoch % Self.secondsPerHour
            let before = perHour[hour] ?? (0, sighting.epoch)
            perHour[hour] = (before.connections + 1, sighting.epoch)
        }
        forgetOld()
        return perHour.keys.sorted().map { ConnectionHour(hourStart: $0, connections: perHour[$0]!.connections, lastEpoch: perHour[$0]!.last) }
    }

    /// Drops process ids that have been quiet for longer than the memory, so the table stays small.
    private mutating func forgetOld() {
        guard let newest = lastSeen.values.max() else { return }
        lastSeen = lastSeen.filter { newest - $0.value <= Self.memorySeconds }
    }
}
