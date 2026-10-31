import Foundation
import RootCore

/// A creator record as read, with whether its seal still matches its fields.
public struct VmOriginRead: Equatable {
    public let record: VmOriginRecord
    public let intact: Bool

    public var createdBy: VmCreatedBy { VmCreatedBy(record, intact: intact) }
}

/// The creator record of every VM the parent made (mcp/SPEC.md section 10.3), kept for good. Rows are only ever added; the one later change is `deleted_at` and
/// `deleted_by`, once, and the database itself refuses anything else. `sign` is the parent's keyed HMAC, so a row someone edited in the database no longer verifies.
public struct VmOriginStore {
    private let database: Database
    private let sign: (String) -> String
    /// The settings row that says the one-time backfill ran.
    public static let backfilledKey = "vm_origin_backfilled_at"
    public static let backfillActor = "admin"

    public init(_ database: Database, sign: @escaping (String) -> String) {
        self.database = database
        self.sign = sign
    }

    /// Writes the record of a VM the parent has just made. Nothing is overwritten: a second record for the same VM id would be a new VM that took a free id.
    public func record(machine: String, workload: String, input: VmOriginInput, createdAt: Int?, backfilled: Bool = false) throws {
        let seal = VmOriginSeal.seal(machineId: machine, workloadId: workload, input: input, createdAt: createdAt, backfilled: backfilled, sign: sign)
        try database.execute("""
            INSERT INTO vm_origin (machine_id, workload_id, kind, actor, person_id, person_name, token_id, token_prefix, client_name, client_version, source_ip, request_id, created_at, backfilled, seal)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(machine), .text(workload), .text(input.kind.rawValue), .text(input.actor), Self.text(input.personId), Self.text(input.personName), Self.text(input.tokenId),
                  Self.text(input.tokenPrefix), Self.text(input.clientName), Self.text(input.clientVersion), Self.text(input.sourceIp), Self.text(input.requestId),
                  createdAt.map(SQLValue.int) ?? .null, .int(backfilled ? 1 : 0), .text(seal)])
    }

    /// The newest record of the VM, checked against its seal. Nil when the parent has none (a VM it did not make).
    public func get(machine: String, workload: String) throws -> VmOriginRead? {
        try database.query("""
            SELECT machine_id, workload_id, kind, actor, person_id, person_name, token_id, token_prefix, client_name, client_version, source_ip, request_id,
                   created_at, backfilled, deleted_at, deleted_by, seal FROM vm_origin
            WHERE machine_id = ? AND workload_id = ? ORDER BY id DESC LIMIT 1
            """, [.text(machine), .text(workload)]).first.map(read)
    }

    /// The short form of every VM of a machine that has a record, newest record per VM.
    public func createdBy(machine: String) throws -> [String: VmCreatedBy] {
        let rows = try database.query("""
            SELECT machine_id, workload_id, kind, actor, person_id, person_name, token_id, token_prefix, client_name, client_version, source_ip, request_id,
                   created_at, backfilled, deleted_at, deleted_by, seal FROM vm_origin
            WHERE machine_id = ? ORDER BY id
            """, [.text(machine)])
        return rows.reduce(into: [:]) { found, row in
            let read = self.read(row)
            found[read.record.workloadId] = read.createdBy
        }
    }

    /// The parent deleted the VM: its newest record notes when and by whom. Does nothing for a VM without a record.
    public func markDeleted(machine: String, workload: String, by actor: String, now: Date) throws {
        try database.execute("""
            UPDATE vm_origin SET deleted_at = ?, deleted_by = ? WHERE id = (SELECT MAX(id) FROM vm_origin WHERE machine_id = ? AND workload_id = ?) AND deleted_at IS NULL
            """, [.int(Int(now.timeIntervalSince1970)), .text(actor), .text(machine), .text(workload)])
    }

    /// Run once at Root start, after the services exist (the seal needs the parent's key): every VM the parent already lists and has no record for is recorded as made
    /// by the admin, marked as recorded afterwards, with no creation time. The settings row is written in the same step, so this never runs again and a VM that shows up
    /// later without a record stays "unknown origin". Returns how many records it wrote.
    @discardableResult
    public func backfillOnce(now: Date) throws -> Int {
        try database.transaction {
            guard try database.query("SELECT 1 AS found FROM settings WHERE key = ?", [.text(Self.backfilledKey)]).isEmpty else { return 0 }
            let missing = try database.query("""
                SELECT machine_id, id FROM workloads WHERE NOT EXISTS (SELECT 1 FROM vm_origin o WHERE o.machine_id = workloads.machine_id AND o.workload_id = workloads.id) ORDER BY machine_id, id
                """)
            for row in missing {
                try record(machine: row.string("machine_id"), workload: row.string("id"), input: VmOriginInput(kind: .panel, actor: Self.backfillActor), createdAt: nil, backfilled: true)
            }
            try database.execute("INSERT INTO settings (key, value) VALUES (?, ?)", [.text(Self.backfilledKey), .text(String(Int(now.timeIntervalSince1970)))])
            return missing.count
        }
    }

    // MARK: reading

    private func read(_ row: Row) -> VmOriginRead {
        let input = VmOriginInput(kind: VmOriginKind(rawValue: row.string("kind")) ?? .panel, actor: row.string("actor"), personId: row.optionalString("person_id"),
                                  personName: row.optionalString("person_name"), tokenId: row.optionalString("token_id"), tokenPrefix: row.optionalString("token_prefix"),
                                  clientName: row.optionalString("client_name"), clientVersion: row.optionalString("client_version"), sourceIp: row.optionalString("source_ip"),
                                  requestId: row.optionalString("request_id"))
        let record = VmOriginRecord(machineId: row.string("machine_id"), workloadId: row.string("workload_id"), input: input, createdAt: row.optionalInt("created_at"),
                                    backfilled: row.int("backfilled") == 1, deletedAt: row.optionalInt("deleted_at"), deletedBy: row.optionalString("deleted_by"), seal: row.string("seal"))
        return VmOriginRead(record: record, intact: VmOriginSeal.isIntact(record, sign: sign))
    }

    private static func text(_ value: String?) -> SQLValue { value.map(SQLValue.text) ?? .null }
}
