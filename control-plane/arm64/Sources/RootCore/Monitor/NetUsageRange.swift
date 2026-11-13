import Foundation

/// The ranges the usage route answers. Each says where its window starts; the window always ends now.
public enum NetUsageRange: String, Equatable, Sendable, CaseIterable {
    case today
    case month
    case thirtyDays = "30d"

    public static let parameter = "range"

    /// Only these texts are accepted. A missing parameter means `today`.
    public struct Refused: Error, Equatable, Sendable {
        public let message = "range must be today, month or 30d"
    }

    /// `values` are all the `range` parameters of the request, in order.
    public static func parse(values: [String]) throws -> NetUsageRange {
        guard !values.isEmpty else { return .today }
        guard values.count == 1, let only = values.first, let range = NetUsageRange(rawValue: only) else { throw Refused() }
        return range
    }

    /// Epoch seconds of the window's start for `now`: local midnight today, the first of the local month, or 30 days back.
    public func start(now: Int, offsetMinutes: Int = NetUsageRules.officeUtcOffsetMinutes) -> Int {
        switch self {
        case .today: return NetUsageClock.localMidnight(now, offsetMinutes: offsetMinutes)
        case .month: return NetUsageClock.localMonthStart(now, offsetMinutes: offsetMinutes)
        case .thirtyDays: return now - NetUsageRules.keepDays * NetUsageRules.secondsPerDay
        }
    }
}

/// The day counts the daily route answers: a week or the 30 days kept.
public enum NetUsageDays: Int, Equatable, Sendable, CaseIterable {
    case week = 7
    case month = 30

    public static let parameter = "days"

    /// Only these numbers are accepted. A missing parameter means 7.
    public struct Refused: Error, Equatable, Sendable {
        public let message = "days must be 7 or 30"
    }

    /// `values` are all the `days` parameters of the request, in order.
    public static func parse(values: [String]) throws -> NetUsageDays {
        guard !values.isEmpty else { return .week }
        guard values.count == 1, let only = values.first, let days = Int(only).flatMap(NetUsageDays.init(rawValue:)) else { throw Refused() }
        return days
    }
}

/// Local-day arithmetic for the office clock. Days are cut at local midnight; no time zone database is needed, only a fixed offset.
enum NetUsageClock {
    /// Epoch seconds of the local midnight that starts the local day of `epoch`.
    static func localMidnight(_ epoch: Int, offsetMinutes: Int) -> Int {
        let offset = offsetMinutes * NetUsageRules.secondsPerMinute
        return (epoch + offset) / NetUsageRules.secondsPerDay * NetUsageRules.secondsPerDay - offset
    }

    /// Epoch seconds of the local midnight that starts the first day of the local month of `epoch`.
    static func localMonthStart(_ epoch: Int, offsetMinutes: Int) -> Int {
        let daysIntoMonth = dayOfMonth(epoch + offsetMinutes * NetUsageRules.secondsPerMinute) - 1
        return localMidnight(epoch, offsetMinutes: offsetMinutes) - daysIntoMonth * NetUsageRules.secondsPerDay
    }

    /// The day of the month (1 to 31) of a time given as local epoch seconds, read in UTC so the fixed offset is the only shift.
    private static func dayOfMonth(_ localSeconds: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.component(.day, from: Date(timeIntervalSince1970: Double(localSeconds)))
    }
}
