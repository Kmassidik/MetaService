import Foundation

/// When each online machine is next sampled. Pure: the caller gives the time and the machines that are online.
/// A machine seen for the first time starts after a delay made from its name, so many machines are not all asked in the same second.
public struct HistorySchedule: Sendable {
    private let interval: TimeInterval
    private var nextDue: [String: Date] = [:]

    public init(intervalSeconds: Int) {
        interval = TimeInterval(max(intervalSeconds, 1))
    }

    /// The machines due now. Each one's next time moves one interval on from the time it was due (not from now), so the rhythm does not drift;
    /// after a long pause it restarts from now instead of firing a burst. A machine that is not online loses its place and starts over, with a new delay, when it comes back.
    public mutating func due(online: [String], now: Date) -> [String] {
        nextDue = nextDue.filter { online.contains($0.key) }
        var due: [String] = []
        for id in online {
            let planned = nextDue[id] ?? now.addingTimeInterval(Self.startDelay(id, within: interval))
            guard planned <= now else { nextDue[id] = planned; continue }
            due.append(id)
            nextDue[id] = Self.following(planned, now: now, interval: interval)
        }
        return due
    }

    /// A delay from 0 up to one interval, always the same for the same name (FNV-1a of the name).
    static func startDelay(_ id: String, within interval: TimeInterval) -> TimeInterval {
        let hash = id.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        return interval * Double(hash % 1000) / 1000
    }

    private static func following(_ planned: Date, now: Date, interval: TimeInterval) -> Date {
        let next = planned.addingTimeInterval(interval)
        return next > now ? next : now.addingTimeInterval(interval)
    }
}
