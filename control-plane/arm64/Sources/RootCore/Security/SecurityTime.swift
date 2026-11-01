import Foundation

/// The time words of the security log. Times are stored as UTC text with seconds, `2026-11-01T08:30:00Z`, so that plain text order is time order.
public enum SecurityTime {
    /// Failed-login counts and events older than this are deleted.
    public static let retentionDays = 90
    /// A helper clock may be a little ahead; an event later than this past `now` is taken as happening now.
    public static let futureSlackSeconds: TimeInterval = 86_400
    /// The ten-minute failed-login buckets of the short ranges are kept this long; the day counts keep `retentionDays`.
    public static let bucketRetentionDays = 8
    /// The length of one failed-login bucket.
    public static let bucketMinutes = 10
    /// How often the old rows are deleted (they are also deleted at start).
    public static let retentionEverySeconds: TimeInterval = 6 * 3_600

    private static let secondsPerDay: TimeInterval = 86_400
    private static let secondsPerMinute: TimeInterval = 60
    private static let dayLength = 10

    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    public static func text(_ date: Date) -> String { formatter(fractional: false).string(from: date) }

    /// The UTC day of a moment, `YYYY-MM-DD`.
    public static func day(_ date: Date) -> String { String(text(date).prefix(dayLength)) }

    /// The start of the ten-minute UTC bucket a moment falls in, as time text (`2026-11-01T08:40:00Z`). A moment on a boundary starts its own bucket.
    public static func bucketStart(_ date: Date) -> String {
        let length = TimeInterval(bucketMinutes) * secondsPerMinute
        let seconds = (date.timeIntervalSince1970 / length).rounded(.down) * length
        return text(Date(timeIntervalSince1970: seconds))
    }

    /// The first bucket start strictly later than a moment: a bucket that began exactly at that moment is left out.
    public static func bucketStartAfter(_ date: Date) -> String {
        let length = TimeInterval(bucketMinutes) * secondsPerMinute
        return text(Date(timeIntervalSince1970: (date.timeIntervalSince1970 / length).rounded(.down) * length + length))
    }

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

    public static func bucketRetentionCutoff(now: Date) -> Date { now.addingTimeInterval(-TimeInterval(bucketRetentionDays) * secondsPerDay) }

    /// True when the old rows are due for deletion: never run yet, or the last run is a full period ago.
    public static func retentionDue(lastRun: Date?, now: Date) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= retentionEverySeconds
    }
}

/// Where the failed-login numbers of a range are read: the UTC day counts, or the ten-minute buckets.
public enum SecurityWindow: Equatable, Sendable {
    /// Day counts from this UTC day (included) on.
    case days(from: String)
    /// Buckets that start at or after this time text (a bucket start).
    case buckets(from: String)
}

/// The ranges of the Security page.
public enum SecurityRange: String, CaseIterable, Sendable {
    case hour = "1h", sixHours = "6h", twelveHours = "12h", day = "24h", week = "7d", month = "30d", quarter = "90d"

    public static let standard = SecurityRange.week
    private static let bucketedUpTo: TimeInterval = 86_400

    public var seconds: TimeInterval {
        switch self {
        case .hour: return 3_600
        case .sixHours: return 6 * 3_600
        case .twelveHours: return 12 * 3_600
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .quarter: return 90 * 86_400
        }
    }

    /// Ranges up to 24 hours are read from the ten-minute buckets; longer ones from the day counts.
    public var usesBuckets: Bool { seconds <= Self.bucketedUpTo }

    public func start(now: Date) -> Date { now.addingTimeInterval(-seconds) }

    /// Failed logins are counted per UTC day, so a long range reaches back to the day it starts on.
    public func firstDay(now: Date) -> String { SecurityTime.day(start(now: now)) }

    /// The failed-login source of this range. A bucket counts when it starts after `now - range`, so a 1 h range holds at most six buckets.
    public func window(now: Date) -> SecurityWindow {
        usesBuckets ? .buckets(from: SecurityTime.bucketStartAfter(start(now: now))) : .days(from: firstDay(now: now))
    }
}
