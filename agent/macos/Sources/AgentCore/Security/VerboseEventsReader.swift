import Foundation

/// Reads the VERBOSE sshd log in fixed windows after a cursor (spec I1, I2), one event per
/// connection (I3), deduped by process id within the memory window (I4).
public actor VerboseEventsReader {
    public typealias ReadLog = @Sendable (_ start: Int, _ end: Int, _ timeout: TimeInterval) async throws -> String

    static let historySeconds = 24 * 3600
    static let windowSeconds = 3600
    static let settleSeconds = 5
    static let budgetSeconds: TimeInterval = 5
    /// A sshd-session process id seen again within this window is the same connection (I4).
    static let dedupeSeconds = 24 * 3600

    private let readLog: ReadLog
    private let now: @Sendable () -> Int
    private let uptime: @Sendable () -> TimeInterval
    private let zone: TimeZone
    private var lastSeen: [Int: (epoch: Int, sighting: VerboseSighting)] = [:]

    public init(zone: TimeZone = .current, now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) },
                uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, readLog: @escaping ReadLog) {
        self.readLog = readLog; self.now = now; self.uptime = uptime; self.zone = zone
    }

    /// Reads from `after` (nil = historySeconds back) forward in windows until the budget runs out.
    public func read(after: String?, limit: Int) async throws -> SecurityEventsPage {
        let current = now()
        let afterSeconds = after.flatMap { SecurityCursor.decode($0) } ?? 0
        var cursor = max(current - Self.historySeconds, afterSeconds)
        let settled = current - Self.settleSeconds
        var events: [SecurityEvent] = []
        let deadline = uptime() + Self.budgetSeconds
        while cursor < settled, events.count < limit, deadline - uptime() > 0 {
            let end = min(cursor + Self.windowSeconds, settled)
            let text: String
            do {
                text = try await readLog(cursor, end, deadline - uptime())
            } catch {
                break // keep the cursor where reading succeeded (I1)
            }
            events += consume(SshVerboseLog.parse(text, zone: zone))
            cursor = end
        }
        forgetOld(until: cursor)
        return SecurityEventsPage(events: events, cursor: SecurityCursor.encode(cursor), reset: false)
    }

    /// Turns the window's sightings into events, one per new pid (I3), in time order.
    private func consume(_ sightings: [VerboseSighting]) -> [SecurityEvent] {
        var events: [SecurityEvent] = []
        for sighting in sightings.sorted(by: { $0.epoch < $1.epoch }) {
            let known = lastSeen[sighting.pid]
            let isNew: Bool
            if let known { isNew = sighting.epoch - known.epoch > Self.dedupeSeconds || sighting.failed != known.sighting.failed } else { isNew = true }
            guard isNew else { continue }
            lastSeen[sighting.pid] = (sighting.epoch, sighting)
            if sighting.failed {
                events.append(SecurityEvent(time: Self.isoTime(sighting.epoch), type: .failedLogin,
                                            user: sighting.user, address: sighting.address, count: 1))
            } else if let method = sighting.method {
                events.append(SecurityEvent(time: Self.isoTime(sighting.epoch), type: .login,
                                            user: sighting.user, address: sighting.address, count: 1))
            }
        }
        return events
    }

    /// Drops pids quiet longer than the dedupe window, so the table stays small.
    private func forgetOld(until cursor: Int) {
        lastSeen = lastSeen.filter { cursor - $0.value.epoch <= Self.dedupeSeconds }
    }

    static func isoTime(_ epoch: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}
