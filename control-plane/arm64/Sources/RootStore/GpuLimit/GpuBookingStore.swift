import Foundation
import RootCore

/// The GPU memory promised to each container, per machine. Workload ids are only unique per machine, so both are in the key.
/// Where it lives: `RootStore/GpuLimit`. Not tied to the workloads table: that one is rewritten by every heartbeat, and a stopped VM must keep its booking.
/// Until a create has made its VM, the booking is kept under the create command's id; `move` gives it the VM's id.
public struct GpuBookingStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    /// Checks that the limit fits and writes the booking, as one step: two requests made at once cannot both count the same free memory.
    /// `room.bookedGb` is ignored; the sum is read inside the same transaction.
    public func book(machine: String, key: String, gb: Int, room: GpuRoom, now: Date) throws {
        try database.transaction {
            let current = GpuRoom(announcesLimit: room.announcesLimit, totalGb: room.totalGb, bookedGb: try bookedGb(machine: machine))
            if let refusal = GpuBooking.refusal(current, requestedGb: gb) { throw refusal }
            try database.execute("""
                INSERT INTO workload_gpu_booking (machine_id, workload_id, gpu_memory_gb, created_at) VALUES (?, ?, ?, ?)
                ON CONFLICT (machine_id, workload_id) DO UPDATE SET gpu_memory_gb = excluded.gpu_memory_gb, created_at = excluded.created_at
                """, [.text(machine), .text(key), .int(gb), .int(Int(now.timeIntervalSince1970))])
        }
    }

    /// The sum of every booking on the machine, stopped VMs and creates still running included.
    public func bookedGb(machine: String) throws -> Int {
        try database.query("SELECT COALESCE(SUM(gpu_memory_gb), 0) AS booked FROM workload_gpu_booking WHERE machine_id = ?", [.text(machine)]).first?.int("booked") ?? 0
    }

    /// Every booking of the machine by workload id (for the machine list).
    public func bookings(machine: String) throws -> [String: Int] {
        let rows = try database.query("SELECT workload_id, gpu_memory_gb FROM workload_gpu_booking WHERE machine_id = ?", [.text(machine)])
        return Dictionary(rows.map { ($0.string("workload_id"), $0.int("gpu_memory_gb")) }, uniquingKeysWith: { first, _ in first })
    }

    /// A create has made its VM: the booking made under the command's id now belongs to the VM.
    public func move(machine: String, from key: String, to workload: String) throws {
        try database.execute("UPDATE OR REPLACE workload_gpu_booking SET workload_id = ? WHERE machine_id = ? AND workload_id = ?", [.text(workload), .text(machine), .text(key)])
    }

    /// The VM is gone, or its create failed: the memory is free again.
    public func release(machine: String, key: String) throws {
        try database.execute("DELETE FROM workload_gpu_booking WHERE machine_id = ? AND workload_id = ?", [.text(machine), .text(key)])
    }

    /// The machine is gone: so is everything promised on it.
    public func release(machine: String) throws {
        try database.execute("DELETE FROM workload_gpu_booking WHERE machine_id = ?", [.text(machine)])
    }
}
