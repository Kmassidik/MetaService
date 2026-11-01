import Foundation

/// The security log lives in its own file, `security.sqlite3` beside `root.sqlite3`, so it can grow and be pruned without touching the main database.
/// It has its own connection and its own `schema_version`.
public enum SecurityDatabase {
    public static let fileName = "security.sqlite3"

    /// Where the file sits for a main database path: in the same folder.
    public static func path(besides mainDatabasePath: String) -> String {
        (mainDatabasePath as NSString).deletingLastPathComponent + "/" + fileName
    }

    /// Opens (creating when needed) and migrates the security database.
    public static func open(path: String) throws -> Database {
        let database = try Database(path: path)
        try Migrations.run(steps, on: database)
        return database
    }

    public static var latest: Int { steps.last?.version ?? 0 }

    /// Numbered schema steps, as in `Migrations`. Add new steps at the end; never edit old ones.
    static let steps: [Migrations.Step] = [
        // machine_state: where each helper's log was read up to, when it last answered, and its latest baseline.
        // failed_daily: failed logins as one count per UTC day, machine, user and address ('' stands for unknown, because a NULL in a key would never match twice); last_seen is the newest event time folded into the row.
        // events: successful logins, blocks and unblocks, one row each; `count` is always 1 here.
        (1, { try $0.exec("""
            CREATE TABLE machine_state (
              machine TEXT PRIMARY KEY, cursor TEXT, last_reported TEXT, baseline_json TEXT
            );
            CREATE TABLE failed_daily (
              day TEXT NOT NULL, machine TEXT NOT NULL, user TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '',
              count INTEGER NOT NULL, last_seen TEXT NOT NULL,
              PRIMARY KEY (day, machine, user, address)
            );
            CREATE INDEX failed_daily_by_machine ON failed_daily (machine, day);
            CREATE INDEX failed_daily_by_address ON failed_daily (address);
            CREATE TABLE events (
              id INTEGER PRIMARY KEY, time TEXT NOT NULL, machine TEXT NOT NULL, type TEXT NOT NULL,
              user TEXT, address TEXT, method TEXT, detail TEXT, until_time TEXT, count INTEGER NOT NULL DEFAULT 1
            );
            CREATE INDEX events_by_time ON events (time);
            CREATE INDEX events_by_machine ON events (machine, time);
            CREATE INDEX events_by_type ON events (type, time);
            CREATE INDEX events_by_address ON events (address);
            """) }),
        // failed_buckets: the same failed logins as failed_daily, but per ten-minute UTC bucket (`bucket_start`, e.g. 2026-11-01T08:40:00Z), for the 1 h to 24 h ranges. Same '' sentinel for unknown user and address. Kept 8 days.
        // failed_slots: both tables in one view, so a query picks the day counts or the buckets with a bound `kind` and its SQL stays fixed text.
        // Only data collected live after this step is precise: a helper catch-up groups one reply per (user, address) with the latest time, so older history lands in one bucket.
        (2, { try $0.exec("""
            CREATE TABLE failed_buckets (
              bucket_start TEXT NOT NULL, machine TEXT NOT NULL, user TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '',
              count INTEGER NOT NULL, last_seen TEXT NOT NULL,
              PRIMARY KEY (bucket_start, machine, user, address)
            );
            CREATE INDEX failed_buckets_by_machine ON failed_buckets (machine, bucket_start);
            CREATE VIEW failed_slots AS
              SELECT 'days' AS kind, day AS slot, machine, user, address, count, last_seen, 'f' || rowid AS id FROM failed_daily
              UNION ALL
              SELECT 'buckets' AS kind, bucket_start AS slot, machine, user, address, count, last_seen, 'b' || rowid AS id FROM failed_buckets;
            """) }),
    ]
}
