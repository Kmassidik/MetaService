import Darwin
import Foundation

/// This computer's own IPv4 addresses on the network (not loopback), to find the one that another computer on the same network can reach.
enum LocalAddresses {
    static func ipv4() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return [] }
        defer { freeifaddrs(first) }
        var found: [String] = []
        for pointer in sequence(first: start, next: { $0.pointee.ifa_next }) {
            guard let address = pointer.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET), pointer.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            if inet_ntop(AF_INET, &value, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil { found.append(String(cString: buffer)) }
        }
        return found
    }
}
