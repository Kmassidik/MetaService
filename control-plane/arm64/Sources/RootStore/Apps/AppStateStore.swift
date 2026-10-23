import Foundation
import RootCore

/// The app wanted inside each VM and how setting it up stands. Workload ids are only unique per machine, so both are in the key.
/// Where it lives: `RootStore/Apps`. Not tied to the workloads table: that one is rewritten by every heartbeat.
public struct AppStateStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    /// An app is wanted in this VM; nothing has started yet. Replaces anything kept before for the same VM id.
    public func recordIntent(app: String, workload: String, machine: String, now: Date) throws {
        try database.execute("""
            INSERT INTO workload_app_state (machine_id, workload_id, app, state, message, version, installer_sha256, log_tail_json, started_at, updated_at)
            VALUES (?, ?, ?, 'none', NULL, NULL, NULL, '[]', NULL, ?)
            ON CONFLICT (machine_id, workload_id) DO UPDATE SET app = excluded.app, state = 'none', message = NULL, version = NULL, installer_sha256 = NULL,
              log_tail_json = '[]', started_at = NULL, updated_at = excluded.updated_at
            """, [.text(machine), .text(workload), .text(app), .int(Int(now.timeIntervalSince1970))])
    }

    public func record(workload: String, machine: String) throws -> AppRecord? {
        try database.query("SELECT * FROM workload_app_state WHERE machine_id = ? AND workload_id = ?", [.text(machine), .text(workload)]).first.map(Self.record(of:))
    }

    /// Every VM of the machine that wants an app, by workload id (for the machine list).
    public func records(machine: String) throws -> [String: AppRecord] {
        let rows = try database.query("SELECT * FROM workload_app_state WHERE machine_id = ?", [.text(machine)])
        return Dictionary(rows.map { ($0.string("workload_id"), Self.record(of: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    /// An install starts: the VM shows "installing" until `finish`. Also the "try again now" of the panel, which clears any wait. Does nothing when no app is wanted.
    public func begin(workload: String, machine: String, now: Date) throws {
        let seconds = Int(now.timeIntervalSince1970)
        try database.execute("""
            UPDATE workload_app_state SET state = 'installing', message = NULL, log_tail_json = '[]', started_at = ?, updated_at = ? WHERE machine_id = ? AND workload_id = ?
            """, [.int(seconds), .int(seconds), .text(machine), .text(workload)])
    }

    public func finish(workload: String, machine: String, as outcome: AppFinish, now: Date) throws {
        let seconds = Int(now.timeIntervalSince1970)
        let (state, message, version, sha, log) = Self.columns(of: outcome)
        try database.execute("""
            UPDATE workload_app_state SET state = ?, message = ?, version = ?, installer_sha256 = ?, log_tail_json = ?, updated_at = ? WHERE machine_id = ? AND workload_id = ?
            """, [.text(state), message.map(SQLValue.text) ?? .null, version.map(SQLValue.text) ?? .null, sha.map(SQLValue.text) ?? .null, .text(try Self.encode(log)),
                  .int(seconds), .text(machine), .text(workload)])
    }

    /// VMs on this machine whose app the heartbeat may start now: wanted and not started, or failed and past the wait. One that is running is left alone.
    public func pendingWorkloads(machine: String, now: Date) throws -> [String] {
        let seconds = Int(now.timeIntervalSince1970)
        return try records(machine: machine).filter { $0.value.mayStartFromHeartbeat(at: seconds) }.map(\.key).sorted()
    }

    /// The VM is gone: so is what was kept for it.
    public func forget(workload: String, machine: String) throws {
        try database.execute("DELETE FROM workload_app_state WHERE machine_id = ? AND workload_id = ?", [.text(machine), .text(workload)])
    }

    /// The machine is gone: so is everything kept for its VMs.
    public func forget(machine: String) throws {
        try database.execute("DELETE FROM workload_app_state WHERE machine_id = ?", [.text(machine)])
    }

    private static func columns(of outcome: AppFinish) -> (state: String, message: String?, version: String?, sha: String?, log: [String]) {
        switch outcome {
        case .ready(let version, let sha): return (AppPhase.ready.rawValue, nil, version, sha, [])
        case .failed(let message, let log): return (AppPhase.failed.rawValue, message, nil, nil, log)
        case .waiting: return (AppPhase.none.rawValue, nil, nil, nil, [])
        }
    }

    private static func record(of row: Row) -> AppRecord {
        AppRecord(app: row.string("app"), phase: AppPhase(rawValue: row.string("state")) ?? .none, message: row.optionalString("message"), version: row.optionalString("version"),
                  installerSha256: row.optionalString("installer_sha256"), logTail: decodeLog(row.string("log_tail_json")), startedAt: row.optionalInt("started_at"), updatedAt: row.int("updated_at"))
    }

    private static func decodeLog(_ text: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
    }

    private static func encode(_ lines: [String]) throws -> String {
        String(decoding: try JSONEncoder().encode(lines), as: UTF8.self)
    }
}
