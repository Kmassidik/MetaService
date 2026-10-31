import Foundation
import RootCore

/// A VM a person asked for. It exists from the create, before the machine has named the VM (`workloadId` is nil until then).
public struct McpWorkloadRow: Equatable {
    public let id: Int
    public let personId: String
    public let tokenId: String
    public let machineId: String
    public let workloadId: String?
    public let requestId: String
    public let commandId: String?
    public let vcpu: Int
    public let ramMb: Int
    public let diskGb: Int
    public let createdAt: Date
}

public struct NewMcpWorkload {
    public let personId: String
    public let tokenId: String
    public let machineId: String
    public let requestId: String
    public let idempotencyKey: String?
    public let wish: McpWish
    public let createdAt: Date

    public init(personId: String, tokenId: String, machineId: String, requestId: String, idempotencyKey: String?, wish: McpWish, createdAt: Date) {
        self.personId = personId
        self.tokenId = tokenId
        self.machineId = machineId
        self.requestId = requestId
        self.idempotencyKey = idempotencyKey
        self.wish = wish
        self.createdAt = createdAt
    }
}

/// Which VMs each person made (mcp/SPEC.md, "Ownership", by person since revision 2). A row stays after its VM is gone, marked deleted, so the creates of the last day can still be counted.
public struct McpWorkloadStore {
    private let database: Database
    public static let daySeconds = 86_400

    public init(_ database: Database) { self.database = database }

    /// Reserves a slot for a VM about to be made: the row exists before the command does, so two creates at once cannot both take the last slot.
    /// The command id is attached once the machine has accepted the order (`attach`), or the row is taken back (`remove`) when it did not.
    public func reserve(_ item: NewMcpWorkload) throws -> Int {
        try database.transaction {
            try database.execute("""
                INSERT INTO token_workloads (person_id, token_id, machine_id, request_id, idempotency_key, vcpu, ram_mb, disk_gb, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(item.personId), .text(item.tokenId), .text(item.machineId), .text(item.requestId), item.idempotencyKey.map(SQLValue.text) ?? .null,
                      .int(item.wish.vcpu), .int(item.wish.ramMb), .int(item.wish.diskGb), .int(McpTokenStore.seconds(item.createdAt))])
            return try database.query("SELECT last_insert_rowid() AS id").first?.int("id") ?? 0
        }
    }

    public func attach(row: Int, command: String) throws {
        try database.execute("UPDATE token_workloads SET command_id = ? WHERE id = ?", [.text(command), .int(row)])
    }

    public func remove(row: Int) throws {
        try database.execute("DELETE FROM token_workloads WHERE id = ?", [.int(row)])
    }

    /// The person's VMs that are not marked deleted, oldest first. Includes the ones still being made.
    public func alive(person: String) throws -> [McpWorkloadRow] {
        try database.query("""
            SELECT id, person_id, token_id, machine_id, workload_id, request_id, command_id, vcpu, ram_mb, disk_gb, created_at FROM token_workloads
            WHERE person_id = ? AND deleted_at IS NULL ORDER BY id
            """, [.text(person)]).map(Self.row)
    }

    /// The live row for a VM of this person, or nil: another person's VM is "no such VM" to this one.
    public func find(person: String, machine: String, workload: String) throws -> McpWorkloadRow? {
        try database.query("""
            SELECT id, person_id, token_id, machine_id, workload_id, request_id, command_id, vcpu, ram_mb, disk_gb, created_at FROM token_workloads
            WHERE person_id = ? AND machine_id = ? AND workload_id = ? AND deleted_at IS NULL
            """, [.text(person), .text(machine), .text(workload)]).first.map(Self.row)
    }

    /// The live row a create request made, whatever the VM's id is yet.
    public func row(request: String) throws -> McpWorkloadRow? {
        try database.query("""
            SELECT id, person_id, token_id, machine_id, workload_id, request_id, command_id, vcpu, ram_mb, disk_gb, created_at FROM token_workloads
            WHERE request_id = ? AND deleted_at IS NULL
            """, [.text(request)]).first.map(Self.row)
    }

    public func setWorkload(row: Int, workload: String) throws {
        try database.execute("UPDATE token_workloads SET workload_id = ? WHERE id = ? AND workload_id IS NULL", [.text(workload), .int(row)])
    }

    public func markDeleted(row: Int, now: Date) throws {
        try database.execute("UPDATE token_workloads SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL", [.int(McpTokenStore.seconds(now)), .int(row)])
    }

    /// Alive VMs and the sums of their sizes, plus the creates made in the last 24 hours, deleted or not. Over all the person's tokens.
    public func usage(person: String, now: Date) throws -> McpUsage {
        let sums = try database.query("""
            SELECT COUNT(*) AS vms, COALESCE(SUM(vcpu), 0) AS vcpu, COALESCE(SUM(ram_mb), 0) AS ram, COALESCE(SUM(disk_gb), 0) AS disk
            FROM token_workloads WHERE person_id = ? AND deleted_at IS NULL
            """, [.text(person)]).first
        let recent = try database.query("SELECT COUNT(*) AS made FROM token_workloads WHERE person_id = ? AND created_at > ?",
                                        [.text(person), .int(McpTokenStore.seconds(now) - Self.daySeconds)]).first?.int("made") ?? 0
        return McpUsage(aliveVms: sums?.int("vms") ?? 0, vcpu: sums?.int("vcpu") ?? 0, ramMb: sums?.int("ram") ?? 0, diskGb: sums?.int("disk") ?? 0, createsLastDay: recent)
    }

    private static func row(_ row: Row) -> McpWorkloadRow {
        McpWorkloadRow(id: row.int("id"), personId: row.string("person_id"), tokenId: row.string("token_id"), machineId: row.string("machine_id"), workloadId: row.optionalString("workload_id"),
                       requestId: row.string("request_id"), commandId: row.optionalString("command_id"), vcpu: row.int("vcpu"), ramMb: row.int("ram_mb"), diskGb: row.int("disk_gb"),
                       createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at"))))
    }
}
