import Foundation

/// The time words of the security log. Times are stored as UTC text with seconds, `2026-11-01T08:30:00Z`, so that plain text order is time order.
public enum SecurityTime {
    /// Failed-login counts and events older than this are deleted.
    public static let retentionDays = 90
    /// A helper clock may be a little ahead; an event later than this past `now` is taken as happening now.
    public static let futureSlackSeconds: TimeInterval = 86_400
    /// How often the old rows are deleted (they are also deleted at start).
    public static let retentionEverySeconds: TimeInterval = 6 * 3_600

    private static let secondsPerDay: TimeInterval = 86_400
    private static let dayLength = 10

    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    public static func text(_ date: Date) -> String { formatter(fractional: false).string(from: date) }

    /// The UTC day of a moment, `YYYY-MM-DD`.
    public static func day(_ date: Date) -> String { String(text(date).prefix(dayLength)) }

    /// Reads an ISO 8601 time with or without fractions and any zone. Nil when it is not one.
    public static func parse(_ text: String) -> Date? {
        formatter(fractional: false).date(from: text) ?? formatter(fractional: true).date(from: text)
    }

    /// A helper's time as a moment. A time too far ahead is taken as `now`; nil when it is not a time.
    public static func normalized(_ text: String, now: Date) -> Date? {
        guard let date = parse(text) else { return nil }
        return date.timeIntervalSince(now) > futureSlackSeconds ? now : date
    }

    public static func retentionCutoff(now: Date) -> Date { now.addingTimeInterval(-TimeInterval(retentionDays) * secondsPerDay) }

    /// True when the old rows are due for deletion: never run yet, or the last run is a full period ago.
    public static func retentionDue(lastRun: Date?, now: Date) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= retentionEverySeconds
    }
}

/// The ranges of the Security page.
public enum SecurityRange: String, CaseIterable, Sendable {
    case day = "24h", week = "7d", month = "30d", quarter = "90d"

    public static let standard = SecurityRange.week

    public var seconds: TimeInterval {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .quarter: return 90 * 86_400
        }
    }

    public func start(now: Date) -> Date { now.addingTimeInterval(-seconds) }

    /// Failed logins are counted per UTC day, so a range reaches back to the day it starts on (24 h covers yesterday and today).
    public func firstDay(now: Date) -> String { SecurityTime.day(start(now: now)) }
}
