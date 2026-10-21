import Darwin
import Foundation

/// Bytes in and out since boot, all running interfaces except loopback added together.
enum DarwinNetwork {
    static func totals() -> (received: UInt64, sent: UInt64) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }
        var received: UInt64 = 0, sent: UInt64 = 0
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let counters = linkCounters(entry.pointee) else { continue }
            received += UInt64(counters.ifi_ibytes)
            sent += UInt64(counters.ifi_obytes)
        }
        return (received, sent)
    }

    private static func linkCounters(_ entry: ifaddrs) -> if_data? {
        let flags = Int32(entry.ifa_flags)
        guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK), flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let data = entry.ifa_data else { return nil }
        return data.assumingMemoryBound(to: if_data.self).pointee
    }
}
