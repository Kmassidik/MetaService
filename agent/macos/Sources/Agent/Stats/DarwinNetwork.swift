import Darwin
import Foundation

/// Bytes in and out, failed packets and packets dropped on the way in, since boot, all running interfaces except loopback added together.
enum DarwinNetwork {
    struct Totals { var received: UInt64 = 0, sent: UInt64 = 0, errorsIn: UInt64 = 0, errorsOut: UInt64 = 0, dropsIn: UInt64 = 0 }

    static func totals() -> Totals {
        var list: UnsafeMutablePointer<ifaddrs>?
        var totals = Totals()
        guard getifaddrs(&list) == 0, let first = list else { return totals }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let counters = linkCounters(entry.pointee) else { continue }
            totals.received += UInt64(counters.ifi_ibytes)
            totals.sent += UInt64(counters.ifi_obytes)
            totals.errorsIn += UInt64(counters.ifi_ierrors)
            totals.errorsOut += UInt64(counters.ifi_oerrors)
            totals.dropsIn += UInt64(counters.ifi_iqdrops)
        }
        return totals
    }

    private static func linkCounters(_ entry: ifaddrs) -> if_data? {
        let flags = Int32(entry.ifa_flags)
        guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK), flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let data = entry.ifa_data else { return nil }
        return data.assumingMemoryBound(to: if_data.self).pointee
    }
}
