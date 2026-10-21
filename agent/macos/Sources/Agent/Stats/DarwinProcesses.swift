import Darwin
import Foundation
import AgentCore

/// The programs this helper's user may look at, through libproc: name, user, CPU time and resident memory only. Never the command line.
/// Without root the system refuses details of other users' programs; those are left out of the list.
final class DarwinProcesses {
    private static let nameBytes = 256
    private var users: [uid_t: String] = [:]
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func list() -> [RawProcess] {
        pids().compactMap(process)
    }

    private func pids() -> [pid_t] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var buffer = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 16)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        return buffer.prefix(Int(filled) / MemoryLayout<pid_t>.size).filter { $0 > 0 }
    }

    private func process(_ pid: pid_t) -> RawProcess? {
        var task = proc_taskinfo(), bsd = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, Int32(MemoryLayout<proc_taskinfo>.size)) == Int32(MemoryLayout<proc_taskinfo>.size),
              proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }
        let ticks = task.pti_total_user + task.pti_total_system
        return RawProcess(pid: Int(pid), name: name(of: pid), user: user(bsd.pbi_uid), cpuNanoseconds: ticks * UInt64(timebase.numer) / UInt64(timebase.denom), memoryBytes: task.pti_resident_size)
    }

    private func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Self.nameBytes)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "?" }
        return String(cString: buffer)
    }

    private func user(_ uid: uid_t) -> String {
        if let known = users[uid] { return known }
        let found = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? String(uid)
        users[uid] = found
        return found
    }
}
