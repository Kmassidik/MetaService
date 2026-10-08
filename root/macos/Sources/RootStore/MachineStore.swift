import Foundation
import RootCore

public enum MachineError: Error, Equatable {
    case exists
    case notFound
}

public struct MachineStore {
    private let database: Database
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(_ database: Database) { self.database = database }

    // MARK: enrolling and authenticating

    public func enroll(name: String, tokenHash: String, ip: String?, now: Date) throws {
        do {
            try database.execute("INSERT INTO machines (id, name, ip, token_hash, enrolled_at) VALUES (?, ?, ?, ?, ?)",
                                 [.text(name), .text(name), ip.map(SQLValue.text) ?? .null, .text(tokenHash), .int(Int(now.timeIntervalSince1970))])
        } catch let error as DatabaseError where error.isConstraint {
            throw MachineError.exists
        }
    }

    /// The machine id that owns this token hash, or nil.
    public func authenticate(tokenHash: String) throws -> String? {
        try database.query("SELECT id FROM machines WHERE token_hash = ?", [.text(tokenHash)]).first?.string("id")
    }

    public func remove(id: String) throws {
        let removed = try database.execute("DELETE FROM machines WHERE id = ?", [.text(id)])
        guard removed == 1 else { throw MachineError.notFound }
    }

    // MARK: heartbeat

    public func recordHeartbeat(machineId: String, request: HeartbeatRequest, ip: String?, now: Date) throws {
        let facts = request.facts
        let seconds = Int(now.timeIntervalSince1970)
        try database.transaction {
            try database.execute("""
                UPDATE machines SET ip = COALESCE(?, ip), os = ?, arch = ?, cpu_cores = ?, ram_total_mb = ?, disk_total_gb = ?,
                  free_ram_mb = ?, free_disk_gb = ?, gpu_json = ?, capabilities_json = ?, bundle_version = ?, last_seen = ?
                WHERE id = ?
                """, [ip.map(SQLValue.text) ?? .null, .text(facts.os), .text(facts.arch), .int(facts.cpuCores), .int(facts.ramTotalMb),
                      .int(facts.diskTotalGb), .int(facts.freeRamMb), .int(facts.freeDiskGb), .text(try json(facts.gpu)),
                      .text(try json(facts.capabilities)), request.bundleVersion.map(SQLValue.text) ?? .null, .int(seconds), .text(machineId)])
            try replaceWorkloads(machineId: machineId, reports: request.workloads, at: seconds)
        }
    }

    private func replaceWorkloads(machineId: String, reports: [WorkloadReport], at seconds: Int) throws {
        try database.execute("DELETE FROM workloads WHERE machine_id = ?", [.text(machineId)])
        for item in reports {
            try database.execute("""
                INSERT INTO workloads (id, machine_id, name, kind, state, cpu, ram_mb, disk_gb, gpu_mode, address, bundle_version, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(item.id), .text(machineId), .text(item.name), .text(item.kind), .text(item.state), .int(item.cpu), .int(item.ramMb),
                      .int(item.diskGb), .text(item.gpuMode), item.address.map(SQLValue.text) ?? .null,
                      item.bundleVersion.map(SQLValue.text) ?? .null, .int(seconds)])
        }
    }

    // MARK: reading for operators

    public func list(now: Date) throws -> [MachineSummary] {
        let rows = try database.query("""
            SELECT id, name, ip, os, arch, cpu_cores, ram_total_mb, disk_total_gb, free_ram_mb, free_disk_gb,
                   gpu_json, capabilities_json, agent_version, bundle_version, last_seen
            FROM machines ORDER BY name
            """)
        return try rows.map { try summary($0, now: now) }
    }

    public func get(id: String, now: Date) throws -> MachineSummary {
        let rows = try database.query("""
            SELECT id, name, ip, os, arch, cpu_cores, ram_total_mb, disk_total_gb, free_ram_mb, free_disk_gb,
                   gpu_json, capabilities_json, agent_version, bundle_version, last_seen
            FROM machines WHERE id = ?
            """, [.text(id)])
        guard let row = rows.first else { throw MachineError.notFound }
        return try summary(row, now: now)
    }

    private func summary(_ row: Row, now: Date) throws -> MachineSummary {
        let workloads = try workloadSummaries(machineId: row.string("id"))
        let lastSeen = row.optionalInt("last_seen").map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let state = MachineStates.derive(lastSeen: lastSeen, now: now, workloadStates: workloads.map(\.state))
        return MachineSummary(
            id: row.string("id"), name: row.string("name"), ip: row.optionalString("ip"), os: row.optionalString("os"),
            arch: row.optionalString("arch"), cpuCores: row.optionalInt("cpu_cores"), ramTotalMb: row.optionalInt("ram_total_mb"),
            diskTotalGb: row.optionalInt("disk_total_gb"), freeRamMb: row.optionalInt("free_ram_mb"), freeDiskGb: row.optionalInt("free_disk_gb"),
            gpu: (try? decoder.decode([GpuInfo].self, from: Data(row.string("gpu_json").utf8))) ?? [],
            capabilities: try? decoder.decode(Capabilities.self, from: Data(row.string("capabilities_json").utf8)),
            agentVersion: row.optionalString("agent_version"), bundleVersion: row.optionalString("bundle_version"),
            state: state.rawValue, lastSeen: row.optionalInt("last_seen").map(Dates.iso), workloads: workloads)
    }

    private func workloadSummaries(machineId: String) throws -> [WorkloadSummary] {
        try database.query("""
            SELECT id, name, kind, state, cpu, ram_mb, disk_gb, gpu_mode, address, bundle_version
            FROM workloads WHERE machine_id = ? ORDER BY name
            """, [.text(machineId)]).map {
            WorkloadSummary(id: $0.string("id"), name: $0.string("name"), kind: $0.string("kind"), state: $0.string("state"),
                            cpu: $0.int("cpu"), ramMb: $0.int("ram_mb"), diskGb: $0.int("disk_gb"), gpuMode: $0.string("gpu_mode"),
                            address: $0.optionalString("address"), bundleVersion: $0.optionalString("bundle_version"))
        }
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(data: try encoder.encode(value), encoding: .utf8) ?? "null"
    }
}
