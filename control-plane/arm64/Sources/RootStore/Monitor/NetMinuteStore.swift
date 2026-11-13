import Foundation
import RootCore

/// Reads and writes the per-minute network usage of the `net_minutes` table. Every query binds its values; nothing is joined into the SQL text.
/// Sums and peaks are computed by the database, so no long list of minutes is loaded into memory.
public struct NetMinuteStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    /// Adds the minutes to the stored ones. A minute written again (a minute still growing, or a flush) adds its bytes and samples and keeps the higher peak.
    public func record(_ minutes: [NetMinute]) throws {
        try database.transaction {
            for minute in minutes {
                _ = try database.execute("""
                    INSERT INTO net_minutes (machine_id, minute, in_bytes, out_bytes, in_peak_bps, out_peak_bps, samples) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (machine_id, minute) DO UPDATE SET
                      in_bytes = in_bytes + excluded.in_bytes, out_bytes = out_bytes + excluded.out_bytes,
                      in_peak_bps = MAX(in_peak_bps, excluded.in_peak_bps), out_peak_bps = MAX(out_peak_bps, excluded.out_peak_bps),
                      samples = samples + excluded.samples
                    """, [.text(minute.machineId), .int(minute.minute), .real(minute.inBytes), .real(minute.outBytes),
                          .real(minute.inPeakBps), .real(minute.outPeakBps), .int(minute.samples)])
            }
        }
    }

    /// The usage of one machine for the window [`since`, `until`) in epoch seconds. A minute counts when it starts inside the window.
    /// Nothing stored in the window: zeros.
    public func usage(machineId: String, since: Int, until: Int) throws -> NetUsageFigures {
        let row = try database.query("""
            SELECT COALESCE(SUM(in_bytes), 0.0) AS in_bytes, COALESCE(SUM(out_bytes), 0.0) AS out_bytes,
                   COALESCE(MAX(in_peak_bps), 0.0) AS in_peak, COALESCE(MAX(out_peak_bps), 0.0) AS out_peak
            FROM net_minutes WHERE machine_id = ? AND minute * 60 >= ? AND minute * 60 < ?
            """, [.text(machineId), .int(since), .int(until)]).first
        return NetUsageFigures(inBytes: row?.optionalDouble("in_bytes") ?? 0, outBytes: row?.optionalDouble("out_bytes") ?? 0,
                               inPeakBps: row?.optionalDouble("in_peak") ?? 0, outPeakBps: row?.optionalDouble("out_peak") ?? 0)
    }

    /// Traffic grouped by local day, oldest first, for the minutes in [`sinceMinute`, `untilMinute`). `offsetMinutes` is the local offset from UTC;
    /// a day starts at its local midnight. Pass a nil machine to add every machine together. At most 31 days.
    public func dailyTotals(machineId: String?, sinceMinute: Int, untilMinute: Int, offsetMinutes: Int) throws -> [NetUsageDay] {
        let offsetSeconds = offsetMinutes * NetUsageRules.secondsPerMinute
        let machine: SQLValue = machineId.map(SQLValue.text) ?? .null
        let rows = try database.query("""
            SELECT (minute * 60 + ?) / ? AS day, SUM(in_bytes) AS in_bytes, SUM(out_bytes) AS out_bytes,
                   MAX(in_peak_bps) AS in_peak, MAX(out_peak_bps) AS out_peak
            FROM net_minutes WHERE minute >= ? AND minute < ? AND (? IS NULL OR machine_id = ?)
            GROUP BY day ORDER BY day ASC LIMIT ?
            """, [.int(offsetSeconds), .int(NetUsageRules.secondsPerDay), .int(sinceMinute), .int(untilMinute), machine, machine, .int(Self.maxDays)])
        return rows.map { row in
            NetUsageDay(dayStart: row.int("day") * NetUsageRules.secondsPerDay - offsetSeconds, inBytes: row.optionalDouble("in_bytes") ?? 0,
                        outBytes: row.optionalDouble("out_bytes") ?? 0, inPeakBps: row.optionalDouble("in_peak") ?? 0,
                        outPeakBps: row.optionalDouble("out_peak") ?? 0)
        }
    }

    /// Deletes every minute that starts before `minute` (a minute index: epoch seconds divided by 60), for every machine.
    public func deleteOlderThan(minute: Int) throws {
        _ = try database.execute("DELETE FROM net_minutes WHERE minute < ?", [.int(minute)])
    }

    /// The most day rows one read returns: a window of 30 days can touch 31 local days.
    static let maxDays = 31
}
