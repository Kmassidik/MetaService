import Foundation
import RootCore

/// What the panel may know about one stored key. The key itself (its base64) is not here.
public struct SshKeyRecord: Encodable, Equatable {
    public let id: String
    public let type: String
    public let fingerprint: String
    public let comment: String
    public let addedAt: Int
}

/// The full list a VM must have, tagged with the change number it was read at, so a finished apply only counts if nothing changed meanwhile.
public struct SshKeySnapshot: Equatable {
    public let lines: [String]
    public let revision: Int
}

public struct SshKeyState: Equatable {
    public let applied: Bool
    /// What the helper last reported (`running`, `installed`, `missing`), or nil if it never has.
    public let sshd: String?
}

public enum SshKeyError: Error, Equatable {
    case duplicate
    case tooMany
    case notFound
}

/// SSH public keys per VM, and whether the machine's helper has them yet. Public keys are not secrets, but the base64 never leaves this store except as the helper's list.
public struct SshKeyStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    public func add(_ key: ParsedSshKey, id: String, workload: String, machine: String, now: Date) throws {
        try database.transaction {
            guard try database.query("SELECT 1 AS found FROM workload_ssh_keys WHERE machine_id = ? AND workload_id = ? AND blob = ?", [.text(machine), .text(workload), .text(key.blob)]).isEmpty else { throw SshKeyError.duplicate }
            let count = try database.query("SELECT COUNT(*) AS total FROM workload_ssh_keys WHERE machine_id = ? AND workload_id = ?", [.text(machine), .text(workload)]).first?.int("total") ?? 0
            guard count < SshKeyRules.maxKeysPerVM else { throw SshKeyError.tooMany }
            try database.execute("""
                INSERT INTO workload_ssh_keys (id, workload_id, machine_id, key_type, blob, comment, fingerprint, added_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(id), .text(workload), .text(machine), .text(key.type), .text(key.blob), .text(key.comment), .text(key.fingerprint), .int(Int(now.timeIntervalSince1970))])
            try markChanged(workload: workload, machine: machine)
        }
    }

    /// Removes one key and returns its fingerprint (for the audit trail).
    public func remove(id: String, workload: String, machine: String) throws -> String {
        try database.transaction {
            guard let found = try database.query("SELECT fingerprint FROM workload_ssh_keys WHERE id = ? AND machine_id = ? AND workload_id = ?", [.text(id), .text(machine), .text(workload)]).first else { throw SshKeyError.notFound }
            try database.execute("DELETE FROM workload_ssh_keys WHERE id = ?", [.text(id)])
            try markChanged(workload: workload, machine: machine)
            return found.string("fingerprint")
        }
    }

    public func list(workload: String, machine: String) throws -> [SshKeyRecord] {
        try database.query("SELECT id, key_type, fingerprint, comment, added_at FROM workload_ssh_keys WHERE machine_id = ? AND workload_id = ? ORDER BY added_at, rowid", [.text(machine), .text(workload)]).map {
            SshKeyRecord(id: $0.string("id"), type: $0.string("key_type"), fingerprint: $0.string("fingerprint"), comment: $0.string("comment"), addedAt: $0.int("added_at"))
        }
    }

    public func state(workload: String, machine: String) throws -> SshKeyState {
        guard let row = try database.query("SELECT applied, sshd FROM workload_ssh_state WHERE machine_id = ? AND workload_id = ?", [.text(machine), .text(workload)]).first else { return SshKeyState(applied: true, sshd: nil) }
        return SshKeyState(applied: row.int("applied") == 1, sshd: row.optionalString("sshd"))
    }

    public func snapshot(workload: String, machine: String) throws -> SshKeySnapshot {
        try database.transaction {
            let lines = try database.query("SELECT key_type, blob, comment FROM workload_ssh_keys WHERE machine_id = ? AND workload_id = ? ORDER BY added_at, rowid", [.text(machine), .text(workload)]).map {
                ParsedSshKey(type: $0.string("key_type"), blob: $0.string("blob"), comment: $0.string("comment"), fingerprint: "").line
            }
            let revision = try database.query("SELECT revision FROM workload_ssh_state WHERE machine_id = ? AND workload_id = ?", [.text(machine), .text(workload)]).first?.int("revision") ?? 0
            return SshKeySnapshot(lines: lines, revision: revision)
        }
    }

    /// The helper's answer to an apply. Counts as done only if no key was added or removed since `revision`; a failed apply keeps what sshd said before.
    public func recordApply(workload: String, machine: String, revision: Int, applied: Bool, sshd: String?) throws {
        try database.execute("""
            UPDATE workload_ssh_state SET applied = ?, sshd = COALESCE(?, sshd) WHERE machine_id = ? AND workload_id = ? AND revision = ?
            """, [.int(applied ? 1 : 0), sshd.map(SQLValue.text) ?? .null, .text(machine), .text(workload), .int(revision)])
    }

    /// VMs on this machine whose keys the helper does not have yet.
    public func pendingWorkloads(machine: String) throws -> [String] {
        try database.query("SELECT workload_id FROM workload_ssh_state WHERE machine_id = ? AND applied = 0", [.text(machine)]).map { $0.string("workload_id") }
    }

    /// The VM is gone: its keys and its state go with it.
    public func forget(workload: String, machine: String) throws {
        try database.transaction {
            try database.execute("DELETE FROM workload_ssh_keys WHERE machine_id = ? AND workload_id = ?", [.text(machine), .text(workload)])
            try database.execute("DELETE FROM workload_ssh_state WHERE machine_id = ? AND workload_id = ?", [.text(machine), .text(workload)])
        }
    }

    /// The machine is gone: so is everything kept for its VMs.
    public func forget(machine: String) throws {
        try database.execute("DELETE FROM workload_ssh_keys WHERE machine_id = ?", [.text(machine)])
        try database.execute("DELETE FROM workload_ssh_state WHERE machine_id = ?", [.text(machine)])
    }

    private func markChanged(workload: String, machine: String) throws {
        try database.execute("""
            INSERT INTO workload_ssh_state (workload_id, machine_id, revision, applied) VALUES (?, ?, 1, 0)
            ON CONFLICT (machine_id, workload_id) DO UPDATE SET revision = revision + 1, applied = 0
            """, [.text(workload), .text(machine)])
    }
}
