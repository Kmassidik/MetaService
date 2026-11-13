import Foundation
import RootCore

/// Reads and writes the probe samples of the `latency_samples` table. Every query binds its values; nothing is joined into the SQL text.
/// The summary and the chart points are computed by the database over the whole window, so no long list of rows is loaded into memory.
public struct LatencyStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    /// Stores the samples. A sample with the same machine and time as one already stored replaces it, so one probe is one row.
    public func record(_ samples: [LatencySample]) throws {
        try database.transaction {
            for sample in samples {
                _ = try database.execute("INSERT OR REPLACE INTO latency_samples (machine_id, at, millis) VALUES (?, ?, ?)",
                                         [.text(sample.machineId), .int(sample.at), sample.millis.map(SQLValue.int) ?? .null])
            }
        }
    }

    /// The raw samples of one machine taken at or after `since` (epoch seconds), oldest first. Used for the one-hour chart only: at most `LatencyTiming.maxSamplesPerRead` rows.
    public func samples(machineId: String, since: Int) throws -> [LatencySample] {
        try database.query("""
            SELECT machine_id, at, millis FROM (
              SELECT machine_id, at, millis FROM latency_samples WHERE machine_id = ? AND at >= ? ORDER BY at DESC LIMIT ?
            ) ORDER BY at ASC
            """, [.text(machineId), .int(since), .int(LatencyTiming.maxSamplesPerRead)]).map(row)
    }

    /// The counts of every sample of one machine taken at or after `since`: how many, how many failed, the average and the largest time of the working ones,
    /// and the newest time. The database does the arithmetic over the whole window.
    public func summary(machineId: String, since: Int) throws -> LatencySummary {
        let counts = try database.query("""
            SELECT COUNT(*) AS n, SUM(CASE WHEN millis IS NULL THEN 1 ELSE 0 END) AS failed, AVG(millis) AS average, MAX(millis) AS slowest
            FROM latency_samples WHERE machine_id = ? AND at >= ?
            """, [.text(machineId), .int(since)]).first
        return LatencySummary.make(count: counts?.int("n") ?? 0, failed: counts?.int("failed") ?? 0, averageMs: counts?.optionalDouble("average"),
                                   maxMs: counts?.optionalInt("slowest"), lastMs: try lastMillis(machineId: machineId))
    }

    /// The time of the newest sample of one machine, or nil when it failed or there is no sample.
    public func lastMillis(machineId: String) throws -> Int? {
        try database.query("SELECT millis FROM latency_samples WHERE machine_id = ? ORDER BY at DESC LIMIT 1", [.text(machineId)]).first?.optionalInt("millis")
    }

    /// One point per bucket of `bucketSeconds` from `since` (a bucket starts at a multiple of its width). A point is the average of the working probes in
    /// its bucket, or nil when every probe in it failed. Oldest first; when there are more buckets than `limit`, the newest are kept.
    public func buckets(machineId: String, since: Int, bucketSeconds: Int, limit: Int) throws -> [LatencyPoint] {
        let rows = try database.query("""
            SELECT (at / ?) * ? AS t, AVG(millis) AS average FROM latency_samples
            WHERE machine_id = ? AND at >= ? GROUP BY t ORDER BY t DESC LIMIT ?
            """, [.int(bucketSeconds), .int(bucketSeconds), .text(machineId), .int(since), .int(limit)])
        return rows.reversed().map { LatencyPoint(t: $0.int("t"), ms: $0.optionalDouble("average")) }
    }

    /// Deletes every sample taken before `epoch` (epoch seconds), for every machine.
    public func deleteOlderThan(_ epoch: Int) throws {
        _ = try database.execute("DELETE FROM latency_samples WHERE at < ?", [.int(epoch)])
    }

    private func row(_ row: Row) -> LatencySample {
        LatencySample(machineId: row.string("machine_id"), at: row.int("at"), millis: row.optionalInt("millis"))
    }
}
