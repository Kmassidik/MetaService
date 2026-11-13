import Foundation
import RootCore

/// Reads and writes the probe samples of the `latency_samples` table. Every query binds its values; nothing is joined into the SQL text.
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

    /// The samples of one machine taken at or after `since` (epoch seconds), oldest first. At most `LatencyTiming.maxSamplesPerRead` rows: the newest are kept.
    public func samples(machineId: String, since: Int) throws -> [LatencySample] {
        try database.query("""
            SELECT machine_id, at, millis FROM (
              SELECT machine_id, at, millis FROM latency_samples WHERE machine_id = ? AND at >= ? ORDER BY at DESC LIMIT ?
            ) ORDER BY at ASC
            """, [.text(machineId), .int(since), .int(LatencyTiming.maxSamplesPerRead)]).map(row)
    }

    /// Deletes every sample taken before `epoch` (epoch seconds), for every machine.
    public func deleteOlderThan(_ epoch: Int) throws {
        _ = try database.execute("DELETE FROM latency_samples WHERE at < ?", [.int(epoch)])
    }

    private func row(_ row: Row) -> LatencySample {
        LatencySample(machineId: row.string("machine_id"), at: row.int("at"), millis: row.optionalInt("millis"))
    }
}
