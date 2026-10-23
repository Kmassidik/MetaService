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
        (7, { try $0.exec("ALTER TABLE machines ADD COLUMN problems_json TEXT NOT NULL DEFAULT '[]';") }),
        (8, { try $0.exec("DROP TABLE IF EXISTS sessions;") }),
        (9, { try $0.exec("""
            CREATE TABLE admin (id INTEGER PRIMARY KEY CHECK (id = 1), username TEXT NOT NULL, salt TEXT NOT NULL, hash TEXT NOT NULL, iterations INTEGER NOT NULL);
            CREATE TABLE sessions (token_hash TEXT PRIMARY KEY, username TEXT NOT NULL, csrf_token TEXT NOT NULL, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL);
            """) }),
        (10, { try $0.exec("CREATE TABLE local_agents (machine TEXT PRIMARY KEY, binary TEXT NOT NULL, arguments_json TEXT NOT NULL, log_path TEXT NOT NULL, port INTEGER NOT NULL);") }),
        (11, { try $0.exec("CREATE TABLE machine_settings (machine TEXT PRIMARY KEY, settings_json TEXT NOT NULL);") }),
        (12, { try $0.exec("CREATE TABLE remote_keys (name TEXT PRIMARY KEY, public_key TEXT NOT NULL, private_sealed TEXT NOT NULL, created_at INTEGER NOT NULL);") }),
        (13, { try $0.exec("""
            CREATE TABLE remote_machines (
              machine TEXT PRIMARY KEY, host TEXT NOT NULL, ssh_port INTEGER NOT NULL, ssh_user TEXT NOT NULL, fingerprint TEXT NOT NULL,
              level TEXT NOT NULL, box TEXT NOT NULL, ssh_dir TEXT NOT NULL, agent_port INTEGER NOT NULL, engine TEXT NOT NULL,
              key_name TEXT, key_file TEXT, key_marker TEXT, key_file_created INTEGER NOT NULL DEFAULT 0, ssh_dir_created INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL
            );
            """) }),
        (14, { try $0.exec("DROP TABLE IF EXISTS scan_results; DROP TABLE IF EXISTS scan_runs;") }),
        // The latest scans are kept again, so Find machines opens on the last result at once and a new scan is only run when asked for.
        (15, { try $0.exec("""
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
        // The old "install on this computer" is gone, and with it the list of programs the parent started itself.
        (16, { try $0.exec("DROP TABLE IF EXISTS local_agents;") }),
        // What engine a machine's helper makes VMs with (name, version, ready), as the helper reports it. The helper's own version goes in the agent_version column that has been there from the start.
        (17, { try $0.exec("ALTER TABLE machines ADD COLUMN engine_json TEXT;") }),
        // Why a VM stopped by itself (the helper's optional stopped_reason, as JSON) and how it came up (systemd or plain). Both are replaced with every heartbeat, so they go when the VM runs again or is gone.
        (18, { try $0.exec("""
            ALTER TABLE workloads ADD COLUMN stopped_reason_json TEXT;
            ALTER TABLE workloads ADD COLUMN init_mode TEXT;
            """) }),
        // Which build of the helper program a machine runs (the SHA-256 of its file, as the helper reports it), replaced with every heartbeat. Null for a helper that does not say.
        (19, { try $0.exec("ALTER TABLE machines ADD COLUMN agent_build TEXT;") }),
        // SSH public keys an operator gave for one VM, and per VM whether the helper has the current list (revision counts changes so a late apply cannot overwrite a newer one). Workload ids are only unique per machine. Not tied to the workloads table: that one is rewritten by every heartbeat.
        (20, { try $0.exec("""
            CREATE TABLE workload_ssh_keys (
              id TEXT PRIMARY KEY, workload_id TEXT NOT NULL, machine_id TEXT NOT NULL, key_type TEXT NOT NULL, blob TEXT NOT NULL,
              comment TEXT NOT NULL, fingerprint TEXT NOT NULL, added_at INTEGER NOT NULL
            );
            CREATE UNIQUE INDEX workload_ssh_keys_blob ON workload_ssh_keys (machine_id, workload_id, blob);
            CREATE TABLE workload_ssh_state (
              workload_id TEXT NOT NULL, machine_id TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0, applied INTEGER NOT NULL DEFAULT 0, sshd TEXT,
              PRIMARY KEY (machine_id, workload_id)
            );
            """) }),
        // Progress of setting up the SSH server inside a VM (idle, installing, failed), the plain reason of a failure, and when the phase began. An install can take minutes, so a phase that began long ago and never ended is read as failed.
        (21, { try $0.exec("""
            ALTER TABLE workload_ssh_state ADD COLUMN sshd_state TEXT NOT NULL DEFAULT 'idle';
            ALTER TABLE workload_ssh_state ADD COLUMN sshd_message TEXT;
            ALTER TABLE workload_ssh_state ADD COLUMN sshd_since INTEGER;
            """) }),
        // The app (OpenClaw, Hermes) an operator wants installed inside a VM, and how setting it up stands (none = wanted, not started; installing; ready; failed) with the plain message, the last installer lines and when it began. Keyed by machine and workload id, not tied to the workloads table.
        (22, { try $0.exec("""
            CREATE TABLE workload_app_state (
              machine_id TEXT NOT NULL, workload_id TEXT NOT NULL, app TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'none', message TEXT, version TEXT, installer_sha256 TEXT,
              log_tail_json TEXT NOT NULL DEFAULT '[]', started_at INTEGER, updated_at INTEGER NOT NULL,
              PRIMARY KEY (machine_id, workload_id)
            );
            """) }),
        // GPU memory promised to containers (a shared slice of a card). A booking is made when a create is accepted (under the create command's id), moves to the VM's id when the create succeeds, and goes when the create fails or the VM is deleted. A stopped VM keeps it. The workloads column holds the limit the helper says a container has, replaced with every heartbeat.
        (23, { try $0.exec("""
            CREATE TABLE workload_gpu_booking (
              machine_id TEXT NOT NULL, workload_id TEXT NOT NULL, gpu_memory_gb INTEGER NOT NULL, created_at INTEGER NOT NULL,
              PRIMARY KEY (machine_id, workload_id)
            );
            ALTER TABLE workloads ADD COLUMN gpu_memory_gb INTEGER;
            """) }),
        // The name of a machine's CPU (cpu_model, cleaned by the parent), replaced with every heartbeat. Null for a helper that does not say.
        (24, { try $0.exec("ALTER TABLE machines ADD COLUMN cpu_model TEXT;") }),
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
