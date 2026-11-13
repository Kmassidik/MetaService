import Foundation

/// The fixed timing of the latency probe: how often it runs, how long one health call may take, and how long the samples are kept.
public enum LatencyTiming {
    public static let intervalSeconds = 10
    public static let answerTimeoutSeconds: TimeInterval = 3
    public static let keepDays = 7
    /// The old samples are deleted once an hour, not on every pass.
    public static let pruneEverySeconds = 3_600
    public static let secondsPerDay = 86_400
    /// A chart never gets more points than this; when a range has more buckets, the newest are kept.
    public static let maxPoints = 1_000
    /// The most samples one read returns; the newest are kept.
    public static let maxSamplesPerRead = 10_000
    static let percentScale = 100.0
    public static let nanosecondsPerMillisecond: UInt64 = 1_000_000
}

/// One probe of one machine: when it ran (epoch seconds) and how many milliseconds the health call took, or nil when it failed or timed out.
public struct LatencySample: Equatable, Sendable {
    public let machineId: String
    public let at: Int
    public let millis: Int?

    public init(machineId: String, at: Int, millis: Int?) {
        self.machineId = machineId
        self.at = at
        self.millis = millis
    }
}

/// The numbers of a run of samples: how many, how many failed, and the average, largest and newest times of the ones that worked.
/// Pure: the caller gives the samples. Empty input gives zeros and no averages.
public struct LatencySummary: Equatable, Sendable {
    public let count: Int
    public let failed: Int
    public let averageMs: Double?
    public let maxMs: Int?
    public let lastMs: Int?
    public let percentFailed: Double

    /// Failed samples count in `count` and `failed`, but never in the averages, the largest time or the last time.
    /// The last time is the newest sample's time, so it is nil when the newest probe failed.
    public static func summarize(_ samples: [LatencySample]) -> LatencySummary {
        let working = samples.compactMap(\.millis)
        let newest = samples.max { $0.at < $1.at }
        return make(count: samples.count, failed: samples.count - working.count,
                    averageMs: working.isEmpty ? nil : Double(working.reduce(0, +)) / Double(working.count),
                    maxMs: working.max(), lastMs: newest?.millis)
    }

    /// Builds the summary from counts, for example counts the database computed over a whole window. Percent failed is worked out here, once, for every caller.
    public static func make(count: Int, failed: Int, averageMs: Double?, maxMs: Int?, lastMs: Int?) -> LatencySummary {
        LatencySummary(count: count, failed: failed, averageMs: averageMs, maxMs: maxMs, lastMs: lastMs,
                       percentFailed: count == 0 ? 0 : Double(failed) * LatencyTiming.percentScale / Double(count))
    }

    public init(count: Int, failed: Int, averageMs: Double?, maxMs: Int?, lastMs: Int?, percentFailed: Double) {
        self.count = count
        self.failed = failed
        self.averageMs = averageMs
        self.maxMs = maxMs
        self.lastMs = lastMs
        self.percentFailed = percentFailed
    }
}

/// Written with explicit nulls when there is no average, largest or last time, so the panel always finds every key.
extension LatencySummary: Encodable {
    private enum CodingKeys: String, CodingKey { case count, failed, averageMs, maxMs, lastMs, percentFailed }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(count, forKey: .count)
        try box.encode(failed, forKey: .failed)
        try box.encode(averageMs, forKey: .averageMs)
        try box.encode(maxMs, forKey: .maxMs)
        try box.encode(lastMs, forKey: .lastMs)
        try box.encode(percentFailed, forKey: .percentFailed)
    }
}

/// One point of a chart: a time (epoch seconds) and a number of milliseconds, or nil when nothing in that time worked.
public struct LatencyPoint: Equatable, Sendable {
    public let t: Int
    public let ms: Double?

    public init(t: Int, ms: Double?) {
        self.t = t
        self.ms = ms
    }
}

/// Written with an explicit null for a failed bucket, so the chart can tell a gap from a missing key.
extension LatencyPoint: Encodable {
    private enum CodingKeys: String, CodingKey { case t, ms }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(t, forKey: .t)
        try box.encode(ms, forKey: .ms)
    }
}

/// Turns samples into chart points. Each bucket becomes one point at the bucket's start, with the average of the working samples in it.
/// A bucket where every probe failed gives a nil point. Only buckets that have samples give a point.
public enum LatencyBuckets {
    /// Groups the samples into buckets of `bucketSeconds`, oldest first. If there are more buckets than `maxPoints`, the newest are kept.
    public static func points(_ samples: [LatencySample], bucketSeconds: Int, maxPoints: Int = LatencyTiming.maxPoints) -> [LatencyPoint] {
        let grouped = Dictionary(grouping: samples) { $0.at / bucketSeconds * bucketSeconds }
        let points = grouped.keys.sorted().map { start in LatencyPoint(t: start, ms: average(grouped[start] ?? [])) }
        return Array(points.suffix(maxPoints))
    }

    /// The average of the working samples, or nil when none worked.
    static func average(_ bucket: [LatencySample]) -> Double? {
        let working = bucket.compactMap(\.millis)
        guard !working.isEmpty else { return nil }
        return Double(working.reduce(0, +)) / Double(working.count)
    }
}

/// The ranges the latency route answers. Each range says how far back it looks and how wide one chart point is.
public enum LatencyRange: String, Equatable, Sendable, CaseIterable {
    case hour = "1h"
    case day = "24h"
    case week = "7d"

    public static let parameter = "range"
    static let hourSeconds = 3_600
    /// One hour keeps each probe as its own point (360 points).
    static let hourBucketSeconds = LatencyTiming.intervalSeconds
    /// A day in 90-second buckets: 960 points, under the 1000 cap.
    static let dayBucketSeconds = 90
    /// A week in 660-second buckets: 916 points, under the 1000 cap.
    static let weekBucketSeconds = 660

    /// Only these texts are accepted. A missing parameter means `1h`.
    public struct Refused: Error, Equatable, Sendable {
        public let message = "range must be 1h, 24h or 7d"
    }

    /// `values` are all the `range` parameters of the request, in order.
    public static func parse(values: [String]) throws -> LatencyRange {
        guard !values.isEmpty else { return .hour }
        guard values.count == 1, let only = values.first, let range = LatencyRange(rawValue: only) else { throw Refused() }
        return range
    }

    /// How far back the samples are read, in seconds.
    public var windowSeconds: Int {
        switch self {
        case .hour: return Self.hourSeconds
        case .day: return LatencyTiming.secondsPerDay
        case .week: return LatencyTiming.keepDays * LatencyTiming.secondsPerDay
        }
    }

    /// The width of one chart point, in seconds.
    public var bucketSeconds: Int {
        switch self {
        case .hour: return Self.hourBucketSeconds
        case .day: return Self.dayBucketSeconds
        case .week: return Self.weekBucketSeconds
        }
    }
}

/// The answer of the latency route, in the shape the panel reads.
public struct LatencyReply: Encodable, Equatable, Sendable {
    public let range: String
    public let intervalSeconds: Int
    public let summary: LatencySummary
    public let points: [LatencyPoint]

    /// The summary covers the whole window (computed by the database); the points are the chart for the range.
    public static func make(range: LatencyRange, summary: LatencySummary, points: [LatencyPoint]) -> LatencyReply {
        LatencyReply(range: range.rawValue, intervalSeconds: LatencyTiming.intervalSeconds, summary: summary, points: points)
    }

    public init(range: String, intervalSeconds: Int, summary: LatencySummary, points: [LatencyPoint]) {
        self.range = range
        self.intervalSeconds = intervalSeconds
        self.summary = summary
        self.points = points
    }
}

/// A machine to probe: its id, and the address and helper port it reported. The probe calls the helper by id, not by address.
public struct LatencyTarget: Equatable, Sendable {
    public let machineId: String
    public let host: String
    public let port: Int

    public init(machineId: String, host: String, port: Int) {
        self.machineId = machineId
        self.host = host
        self.port = port
    }
}

/// Times one health call to a machine's helper and reports the milliseconds it took, or nil when it failed or timed out.
public protocol LatencyConnector: Sendable {
    func answerMillis(for target: LatencyTarget, timeout: TimeInterval) async -> Int?
}

/// One pass of the probe: every target is probed at the same time, and each result becomes one sample at the same time.
public enum LatencyRound {
    public static func run(_ targets: [LatencyTarget], at seconds: Int, connector: LatencyConnector, timeout: TimeInterval) async -> [LatencySample] {
        await withTaskGroup(of: LatencySample.self) { group in
            for target in targets {
                group.addTask {
                    let millis = await connector.answerMillis(for: target, timeout: timeout)
                    return LatencySample(machineId: target.machineId, at: seconds, millis: millis)
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
    }
}
