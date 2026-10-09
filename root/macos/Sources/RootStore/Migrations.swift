import Foundation

/// Numbered schema steps. A step runs once, in order, inside a transaction. Add new steps at the end; never edit old ones.
public enum Migrations {
    static let steps: [(version: Int, apply: (Database) throws -> Void)] = [
        (1, { try $0.exec("""
            CREATE TABLE machines (
              id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, ip TEXT,
              os TEXT, arch TEXT, cpu_cores INTEGER, ram_total_mb INTEGER, disk_total_gb INTEGER,
              free_ram_mb INTEGER, free_disk_gb INTEGER,
              gpu_json TEXT NOT NULL DEFAULT '[]', capabilities_json TEXT NOT NULL DEFAULT '{}',
              agent_version TEXT, bundle_version TEXT,
              token_hash TEXT NOT NULL UNIQUE, enrolled_at INTEGER NOT NULL, last_seen INTEGER
            );
            CREATE TABLE workloads (
              id TEXT NOT NULL, machine_id TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
              name TEXT NOT NULL, kind TEXT NOT NULL, state TEXT NOT NULL,
              cpu INTEGER NOT NULL, ram_mb INTEGER NOT NULL, disk_gb INTEGER NOT NULL,
              gpu_mode TEXT NOT NULL, address TEXT, bundle_version TEXT, updated_at INTEGER NOT NULL,
              PRIMARY KEY (machine_id, id)
            );
            CREATE TABLE commands (
              id TEXT PRIMARY KEY, machine_id TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
              workload_id TEXT, type TEXT NOT NULL, params_json TEXT NOT NULL DEFAULT '{}',
              state TEXT NOT NULL, result_json TEXT, actor TEXT NOT NULL,
              created_at INTEGER NOT NULL, finished_at INTEGER
            );
            CREATE TABLE audit_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, actor TEXT NOT NULL,
              action TEXT NOT NULL, target TEXT, detail TEXT NOT NULL DEFAULT '{}'
            );
            CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_log BEGIN SELECT RAISE(ABORT, 'audit log is append only'); END;
            CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_log BEGIN SELECT RAISE(ABORT, 'audit log is append only'); END;
            CREATE TABLE enrollments (
              id INTEGER PRIMARY KEY AUTOINCREMENT, token_hash TEXT NOT NULL UNIQUE, machine_name TEXT NOT NULL,
              created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, used_at INTEGER
            );
            CREATE TABLE sessions (
              token_hash TEXT PRIMARY KEY, email TEXT NOT NULL, csrf_token TEXT NOT NULL,
              created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL
            );
            CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """) }),
        (2, { try $0.exec("""
            CREATE TABLE scan_runs (
              id INTEGER PRIMARY KEY AUTOINCREMENT, actor TEXT NOT NULL, subnet TEXT NOT NULL,
              state TEXT NOT NULL, sources_json TEXT NOT NULL DEFAULT '{}',
              started_at INTEGER NOT NULL, finished_at INTEGER
            );
            CREATE TABLE scan_results (
              id INTEGER PRIMARY KEY AUTOINCREMENT, run_id INTEGER NOT NULL REFERENCES scan_runs(id) ON DELETE CASCADE,
              ip TEXT NOT NULL, mac TEXT, hostname TEXT, vendor TEXT, seen_by TEXT NOT NULL, agent_port_open INTEGER NOT NULL DEFAULT 0,
              UNIQUE (run_id, ip)
            );
            """) }),
        (3, { try $0.exec("ALTER TABLE enrollments ADD COLUMN expected_ip TEXT;") }),
        (4, { try $0.exec("""
            ALTER TABLE machines ADD COLUMN command_token_sealed TEXT;
            ALTER TABLE machines ADD COLUMN agent_port INTEGER NOT NULL DEFAULT 9101;
            CREATE INDEX commands_by_state ON commands (state);
            """) }),
        (5, { try $0.exec("""
            CREATE TABLE bundles (
              version TEXT NOT NULL, platform TEXT NOT NULL, sha256 TEXT NOT NULL, size INTEGER NOT NULL, file TEXT NOT NULL, added_at INTEGER NOT NULL,
              PRIMARY KEY (version, platform)
            );
            CREATE TABLE bundle_pins (id INTEGER PRIMARY KEY AUTOINCREMENT, version TEXT NOT NULL, pinned_at INTEGER NOT NULL, actor TEXT NOT NULL);
            CREATE TABLE chat_access (target TEXT PRIMARY KEY, key_sealed TEXT NOT NULL, port INTEGER NOT NULL, updated_at INTEGER NOT NULL);
            """) }),
        (6, { try $0.exec("""
            CREATE TABLE brain_capabilities (token_hash TEXT PRIMARY KEY, machine TEXT NOT NULL, workload TEXT, expires_at INTEGER NOT NULL);
            CREATE TABLE brain_usage (
              machine TEXT NOT NULL, workload TEXT NOT NULL, requests INTEGER NOT NULL, prompt_tokens INTEGER NOT NULL, completion_tokens INTEGER NOT NULL,
              updated_at INTEGER NOT NULL, PRIMARY KEY (machine, workload)
            );
            """) }),
    ]

    public static var latest: Int { steps.last?.version ?? 0 }

    public static func migrate(_ database: Database) throws {
        try database.exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")
        let current = try database.query("SELECT COALESCE(MAX(version), 0) AS version FROM schema_version").first?.int("version") ?? 0
        for step in steps where step.version > current {
            try database.transaction {
                try step.apply(database)
                try database.execute("INSERT INTO schema_version (version) VALUES (?)", [.int(step.version)])
            }
        }
    }
}
