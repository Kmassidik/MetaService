import Darwin
import Foundation
import AgentCore

/// Memory from the kernel's page counters. Cached = file cache and purgeable pages the system can give back; used = what is left after free and cached.
enum DarwinMemory {
    static func read() throws -> MemoryReading {
        var vm = vm_statistics64(), count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard status == KERN_SUCCESS else { throw StatsReadError.memory }
        let page = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        let free = min(total, UInt64(vm.free_count) * page)
        let cached = min(total - free, (UInt64(vm.external_page_count) + UInt64(vm.purgeable_count)) * page)
        let swap = swapUsage()
        return MemoryReading(totalBytes: total, usedBytes: total - free - cached, cachedBytes: cached, freeBytes: free, swapTotalBytes: swap.total, swapUsedBytes: swap.used)
    }

    private static func swapUsage() -> (total: UInt64, used: UInt64) {
        var usage = xsw_usage(), size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_total, usage.xsu_used)
    }
}
