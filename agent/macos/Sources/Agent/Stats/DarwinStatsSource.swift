import Darwin
import Foundation
import AgentCore

enum StatsReadError: Error { case cpu, memory, boot }

/// Reads this Mac's real numbers. No root needed, nothing is installed, nothing is written.
final class DarwinStatsSource: StatsSource {
    private let processes = DarwinProcesses()

    func read() throws -> StatsSnapshot {
        let (received, sent) = DarwinNetwork.totals()
        return StatsSnapshot(takenAt: Date(), uptimeSeconds: try Self.uptimeSeconds(), cores: try Self.cores(), load: Self.load(), memory: try DarwinMemory.read(),
                             disks: DarwinDisks.read(), receivedTotalBytes: received, sentTotalBytes: sent, processes: processes.list())
    }

    private static func cores() throws -> [CoreTicks] {
        var count: natural_t = 0, info: processor_info_array_t?, infoCount: mach_msg_type_number_t = 0
        let status = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard status == KERN_SUCCESS, let info else { throw StatsReadError.cpu }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { core in
            func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[core * states + Int(state)])) }
            let busy = ticks(CPU_STATE_USER) + ticks(CPU_STATE_SYSTEM) + ticks(CPU_STATE_NICE)
            return CoreTicks(busy: busy, total: busy + ticks(CPU_STATE_IDLE))
        }
    }

    private static func load() -> [Double?] {
        var averages = [Double](repeating: 0, count: 3)
        guard getloadavg(&averages, 3) == 3 else { return [nil, nil, nil] }
        return averages
    }

    private static func uptimeSeconds() throws -> Int {
        var boot = timeval(), size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { throw StatsReadError.boot }
        return max(0, Int(Date().timeIntervalSince1970) - boot.tv_sec)
    }
}
