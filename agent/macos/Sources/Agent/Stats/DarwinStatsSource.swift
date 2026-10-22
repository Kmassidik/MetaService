import Darwin
import Foundation
import AgentCore

enum StatsReadError: Error { case cpu, memory, boot }

/// Reads this Mac's real numbers. No root needed, nothing is installed, nothing is written.
final class DarwinStatsSource: StatsSource {
    private let processes = DarwinProcesses()

    func read(includeProcesses: Bool) throws -> StatsSnapshot {
        let network = DarwinNetwork.totals()
        let (cores, states) = try Self.cpuTimes()
        let extras = StatsExtras(cpuStates: states, topology: topology, networkIssues: NetworkIssues(errorsIn: network.errorsIn, errorsOut: network.errorsOut, dropsIn: network.dropsIn),
                                 diskTotals: DarwinDiskTotals.read(), processCount: processes.count(), gpus: DarwinGpus.read())
        return StatsSnapshot(takenAt: Date(), uptimeSeconds: try Self.uptimeSeconds(), cores: cores, load: Self.load(), memory: try DarwinMemory.read(),
                             disks: DarwinDisks.read(), receivedTotalBytes: network.received, sentTotalBytes: network.sent, processes: includeProcesses ? processes.list() : nil, extras: extras)
    }

    /// The core layout does not change while the helper runs: read once.
    private let topology = DarwinTopology.read()

    private static func cpuTimes() throws -> (cores: [CoreTicks], states: CpuStateTicks) {
        var count: natural_t = 0, info: processor_info_array_t?, infoCount: mach_msg_type_number_t = 0
        let status = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard status == KERN_SUCCESS, let info else { throw StatsReadError.cpu }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        let states = Int(CPU_STATE_MAX)
        func ticks(_ core: Int, _ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[core * states + Int(state)])) }
        let range = 0..<Int(count)
        let cores = range.map { core in
            let busy = ticks(core, CPU_STATE_USER) + ticks(core, CPU_STATE_SYSTEM) + ticks(core, CPU_STATE_NICE)
            return CoreTicks(busy: busy, total: busy + ticks(core, CPU_STATE_IDLE))
        }
        func sum(_ state: Int32) -> UInt64 { range.reduce(UInt64(0)) { $0 + ticks($1, state) } }
        return (cores, CpuStateTicks(user: sum(CPU_STATE_USER), system: sum(CPU_STATE_SYSTEM), nice: sum(CPU_STATE_NICE), idle: sum(CPU_STATE_IDLE)))
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
