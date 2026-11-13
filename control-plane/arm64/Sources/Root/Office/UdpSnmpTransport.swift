import Foundation
import RootCore

/// Sends one SNMP request to an IPv4 agent on UDP port 161 and waits for one reply.
/// Uses a connected BSD datagram socket. The socket is closed on every path, including errors.
public struct UdpSnmpTransport: SnmpTransport {
    private static let snmpPort: UInt16 = 161
    private static let maxDatagramBytes = 4096
    private static let millisecondsPerSecond = 1000.0
    private static let maxPollMilliseconds: Int32 = 60_000

    private let agentAddress: in_addr_t

    /// Accepts only dotted-quad IPv4 text such as "192.0.2.1". Host names and IPv6 are refused.
    public init(ipv4Address text: String) throws {
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1 else {
            throw SnmpError.transportFailed("address is not IPv4 text")
        }
        agentAddress = address.s_addr
    }

    /// Sends `request` and returns the first datagram that comes back within `timeout` seconds.
    public func exchange(_ request: [UInt8], timeout: TimeInterval) async throws -> [UInt8] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else {
            throw SnmpError.transportFailed("socket")
        }
        defer { close(descriptor) }
        try connectSocket(descriptor)
        try sendRequest(request, on: descriptor)
        try awaitReply(on: descriptor, timeout: timeout)
        return try receiveReply(on: descriptor)
    }

    /// Points the socket at the agent. A connected UDP socket only accepts datagrams from that agent.
    private func connectSocket(_ descriptor: Int32) throws {
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = UdpSnmpTransport.snmpPort.bigEndian
        target.sin_addr = in_addr(s_addr: agentAddress)
        let length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafePointer(to: target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, length)
            }
        }
        guard status == 0 else {
            throw SnmpError.transportFailed("connect")
        }
    }

    /// Writes the whole request in one datagram.
    private func sendRequest(_ request: [UInt8], on descriptor: Int32) throws {
        let sent = send(descriptor, request, request.count, 0)
        guard sent == request.count else {
            throw SnmpError.transportFailed("send")
        }
    }

    /// Waits until a reply is readable. A poll that returns nothing is a timeout.
    private func awaitReply(on descriptor: Int32, timeout: TimeInterval) throws {
        var watched = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&watched, 1, UdpSnmpTransport.pollMilliseconds(timeout))
        guard ready != 0 else {
            throw SnmpError.timeout
        }
        guard ready > 0 else {
            throw SnmpError.transportFailed("poll")
        }
    }

    /// Converts seconds to poll milliseconds, clamped to a safe range.
    private static func pollMilliseconds(_ timeout: TimeInterval) -> Int32 {
        let milliseconds = (timeout * millisecondsPerSecond).rounded(.up)
        guard milliseconds.isFinite else {
            return maxPollMilliseconds
        }
        return Int32(min(max(milliseconds, 0), Double(maxPollMilliseconds)))
    }

    /// Reads one datagram of at most `maxDatagramBytes`.
    private func receiveReply(on descriptor: Int32) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: UdpSnmpTransport.maxDatagramBytes)
        let received = recv(descriptor, &buffer, buffer.count, 0)
        guard received >= 0 else {
            throw SnmpError.transportFailed("recv")
        }
        return Array(buffer.prefix(received))
    }
}
