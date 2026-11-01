import Foundation

/// What one read of the log gave: the events, and the cursor to ask from next time.
public struct SecurityEventsPage: Equatable {
    public let events: [SecurityEvent]
    public let cursor: String
    public let reset: Bool
}

/// Turns the SSH connections in the macOS log into one `failed_login` event per hour (see SshConnectionLog for why nothing finer is possible).
/// The log is asked only for the window after the cursor, one hour at a time, and a call stops when its time budget is used up; the cursor then
/// sits where reading stopped, so the next call (the parent calls every minute) goes on from there. The budget must stay well under the parent's
/// own time limit for this route (10 s), or the parent gives up before the answer comes and never stores the cursor.
public actor SecurityEventsReader {
    /// Asks the system log for the `sshd-session` lines between two Unix seconds (start included, end excluded) and gives the compact text.
    public typealias ReadLog = @Sendable (_ start: Int, _ end: Int, _ timeout: TimeInterval) async throws -> String

    public static let detail = "SSH connections (macOS does not log who tried)"
    /// A first call reaches back this far; at about a second per window the catch-up takes a few calls.
    public static let historySeconds = 24 * 3600
    /// One hour is a second or so of `log show` on a busy Mac, so even the first window fits the budget.
    public static let windowSeconds = 3600
    /// The newest seconds are left for the next call, so a connection still being logged is not cut in two.
    public static let settleSeconds = 5
    public static let budgetSeconds: TimeInterval = 5

    private let readLog: ReadLog
    private let now: @Sendable () -> Int
    private let uptime: @Sendable () -> TimeInterval
    private let zone: TimeZone
    private let budget: TimeInterval
    private let history: Int
    private let window: Int
    private var counter = ConnectionCounter()
    /// Where the counter has read up to; a cursor that is not this one means the counter's memory does not fit and it starts empty.
    private var position: Int?

    public init(zone: TimeZone = .current, budget: TimeInterval = SecurityEventsReader.budgetSeconds, history: Int = SecurityEventsReader.historySeconds, window: Int = SecurityEventsReader.windowSeconds, now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) },
                uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, readLog: @escaping ReadLog) {
        self.readLog = readLog; self.now = now; self.uptime = uptime; self.zone = zone; self.budget = budget; self.history = history; self.window = window
    }

    public func read(after: String?, limit: Int) async throws -> SecurityEventsPage {
        let current = now()
        let (from, reset) = Self.startOfRead(after: after, now: current, history: history)
        if from != position { counter = ConnectionCounter() }
        let settled = current - Self.settleSeconds
        var cursor = from
        var events: [SecurityEvent] = []
        let deadline = uptime() + budget
        while cursor < settled, events.count < limit, deadline - uptime() > 0 {
            let end = min(cursor + window, settled)
            let window: Window
            do {
                window = try await consume(from: cursor, to: end, room: limit - events.count, timeout: deadline - uptime())
            } catch where cursor != from {
                break
            }
            events += window.events
            cursor = window.nextCursor
        }
        position = cursor
        return SecurityEventsPage(events: events, cursor: SecurityCursor.encode(cursor), reset: reset)
    }

    // MARK: windows

    private struct Window { let events: [SecurityEvent]; let nextCursor: Int }

    /// Reads one window. When it holds more hours than `room`, only whole hours that fit are taken and the cursor stops at the end of the last one.
    private func consume(from start: Int, to end: Int, room: Int, timeout: TimeInterval) async throws -> Window {
        let text: String
        do {
            text = try await readLog(start, end, timeout)
        } catch {
            throw SecurityLogFailure("the macOS log could not be read: \(error)")
        }
        let sightings = SshConnectionLog.parse(text, zone: zone).filter { $0.epoch >= start && $0.epoch < end }
        var trial = counter
        let hours = trial.count(sightings)
        guard hours.count > room else {
            counter = trial
            return Window(events: hours.map(Self.event), nextCursor: end)
        }
        let kept = Array(hours.prefix(room))
        let cut = min(end, kept[room - 1].hourStart + ConnectionCounter.secondsPerHour)
        _ = counter.count(sightings.filter { $0.epoch < cut })
        return Window(events: kept.map(Self.event), nextCursor: cut)
    }

    private static func event(_ hour: ConnectionHour) -> SecurityEvent {
        SecurityEvent(time: isoTime(hour.lastEpoch), type: .failedLogin, count: hour.connections, detail: detail)
    }

    static func isoTime(_ epoch: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    // MARK: cursor

    /// Where to start reading, and whether the parent must drop what it holds (`reset`): a garbled cursor, one from the future, or one older than the history we keep.
    static func startOfRead(after: String?, now: Int, history: Int) -> (start: Int, reset: Bool) {
        let oldest = now - history
        guard let after else { return (oldest, false) }
        guard let seconds = SecurityCursor.decode(after), seconds <= now else { return (oldest, true) }
        guard seconds >= oldest else { return (oldest, true) }
        return (seconds, false)
    }
}
