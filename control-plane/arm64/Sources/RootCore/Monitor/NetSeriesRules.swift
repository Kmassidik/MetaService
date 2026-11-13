import Foundation

/// The ranges the network series route answers. Each range says how far back it looks and how wide one chart point is.
public enum NetSeriesRange: String, Equatable, Sendable, CaseIterable {
    case h24 = "24h"
    case d7 = "7d"
    case d30 = "30d"

    public static let parameter = "range"
    /// The most points one series returns; the newest are kept.
    public static let maxPoints = 1_000
    /// The message of the 400 answer for any other text.
    public static let refusalMessage = "range must be 24h, 7d or 30d"
    static let weekDays = 7
    static let twentyFourHourBucketSeconds = 120
    static let weekBucketSeconds = 900
    static let thirtyDayBucketSeconds = 3_600

    /// Parses the `range` parameter: nil (missing) is `24h`; any text that is not a range is nil.
    public static func parse(_ text: String?) -> NetSeriesRange? {
        guard let text else { return .h24 }
        return NetSeriesRange(rawValue: text)
    }

    /// How far back the window starts, in seconds.
    public var windowSeconds: Int {
        switch self {
        case .h24: return NetUsageRules.secondsPerDay
        case .d7: return Self.weekDays * NetUsageRules.secondsPerDay
        case .d30: return NetUsageRules.keepDays * NetUsageRules.secondsPerDay
        }
    }

    /// The width of one point, in seconds.
    public var bucketSeconds: Int {
        switch self {
        case .h24: return Self.twentyFourHourBucketSeconds
        case .d7: return Self.weekBucketSeconds
        case .d30: return Self.thirtyDayBucketSeconds
        }
    }

    /// Epoch seconds of the window's start for `now`.
    public func start(now: Int) -> Int {
        now - windowSeconds
    }
}

/// One chart point: the start of its bucket (epoch seconds), the average speed of each direction over the whole bucket, and the fastest minute of each direction.
public struct NetSeriesPoint: Equatable, Sendable, Encodable {
    public let t: Int
    public let inBps: Double
    public let outBps: Double
    public let inPeakBps: Double
    public let outPeakBps: Double

    public init(t: Int, inBps: Double, outBps: Double, inPeakBps: Double, outPeakBps: Double) {
        self.t = t
        self.inBps = inBps
        self.outBps = outBps
        self.inPeakBps = inPeakBps
        self.outPeakBps = outPeakBps
    }

    /// Builds the point of one bucket. The speeds divide the bytes by the whole bucket width, so a quiet bucket stays small.
    public static func fromBucket(start: Int, inBytes: Double, outBytes: Double, inPeakBps: Double, outPeakBps: Double, bucketSeconds: Int) -> NetSeriesPoint {
        let width = Double(bucketSeconds)
        return NetSeriesPoint(t: start, inBps: inBytes / width, outBps: outBytes / width, inPeakBps: inPeakBps, outPeakBps: outPeakBps)
    }

    /// Keys in snake_case, as the panel reads them.
    private enum CodingKeys: String, CodingKey { case t, inBps = "in_bps", outBps = "out_bps", inPeakBps = "in_peak_bps", outPeakBps = "out_peak_bps" }
}

/// The answer of the network series route: the bucket width and the points, oldest first.
public struct NetSeriesReply: Equatable, Sendable, Encodable {
    public let range: String
    public let bucketSeconds: Int
    public let points: [NetSeriesPoint]

    public init(range: String, bucketSeconds: Int, points: [NetSeriesPoint]) {
        self.range = range
        self.bucketSeconds = bucketSeconds
        self.points = points
    }

    /// Keys in snake_case, as the panel reads them.
    private enum CodingKeys: String, CodingKey { case range, bucketSeconds = "bucket_seconds", points }
}
