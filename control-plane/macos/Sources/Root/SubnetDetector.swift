import Darwin
import Foundation
import RootCore

/// Finds the private IPv4 network this machine is on, for when SCAN_SUBNET is not set.
enum SubnetDetector {
    static func detect() -> Subnet? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            if let found = subnet(of: pointer.pointee) { return found }
        }
        return nil
    }

    private static func subnet(of entry: ifaddrs) -> Subnet? {
        let flags = Int32(entry.ifa_flags)
        guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let address = entry.ifa_addr, let mask = entry.ifa_netmask,
              address.pointee.sa_family == UInt8(AF_INET) else { return nil }
        let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
        let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
        let prefix = netmask.nonzeroBitCount
        guard let found = Subnet(cidr: "\(Subnet.text(ip & netmask))/\(prefix)"), found.isPrivate else { return nil }
        return found
    }
}
