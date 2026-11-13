import Foundation

/// The fixed timing of the latency probe: how often it runs, how long one connection may take, and how long the samples are kept.
public enum LatencyTiming {
    public static let intervalSeconds = 10
    public static let connectTimeoutSeconds: TimeInterval = 3
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

/// One probe of one machine: when it ran (epoch seconds) and how many milliseconds the connection took, or nil when it failed or timed out.
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
        let failed = samples.count - working.count
        let newest = samples.max { $0.at < $1.at }
        return LatencySummary(
            count: samples.count,
            failed: failed,
            averageMs: working.isEmpty ? nil : Double(working.reduce(0, +)) / Double(working.count),
            maxMs: working.max(),
            lastMs: newest?.millis,
            percentFailed: samples.isEmpty ? 0 : Double(failed) * LatencyTiming.percentScale / Double(samples.count))
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

    /// The width of one chart point, in seconds. One hour keeps each probe as its own point.
    public var bucketSeconds: Int {
        switch self {
        case .hour: return LatencyTiming.intervalSeconds
        case .day: return 60
        case .week: return 600
        }
    }
}

/// The answer of the latency route, in the shape the panel reads.
public struct LatencyReply: Encodable, Equatable, Sendable {
    public let range: String
    public let intervalSeconds: Int
    public let summary: LatencySummary
    public let points: [LatencyPoint]

    /// The summary covers every sample read; the points are the chart for the range.
    public static func make(range: LatencyRange, samples: [LatencySample]) -> LatencyReply {
        LatencyReply(range: range.rawValue, intervalSeconds: LatencyTiming.intervalSeconds, summary: LatencySummary.summarize(samples),
                     points: LatencyBuckets.points(samples, bucketSeconds: range.bucketSeconds))
    }

    public init(range: String, intervalSeconds: Int, summary: LatencySummary, points: [LatencyPoint]) {
        self.range = range
        self.intervalSeconds = intervalSeconds
        self.summary = summary
        self.points = points
    }
}

/// A machine to probe: its id, and the address and helper port to connect to.
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

/// Opens one TCP connection and reports how many milliseconds it took to be ready, or nil when it failed or timed out. Sends no data.
public protocol LatencyConnector: Sendable {
    func connectMillis(host: String, port: Int, timeout: TimeInterval) async -> Int?
}

/// One pass of the probe: every target is probed at the same time, and each result becomes one sample at the same time.
public enum LatencyRound {
    public static func run(_ targets: [LatencyTarget], at seconds: Int, connector: LatencyConnector, timeout: TimeInterval) async -> [LatencySample] {
        await withTaskGroup(of: LatencySample.self) { group in
            for target in targets {
                group.addTask {
                    let millis = await connector.connectMillis(host: target.host, port: target.port, timeout: timeout)
                    return LatencySample(machineId: target.machineId, at: seconds, millis: millis)
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
    }
}
