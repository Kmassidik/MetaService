import Foundation

/// An IPv4 network such as 192.168.100.0/24. The scan only ever targets one the Root itself decided on.
public struct Subnet: Equatable, CustomStringConvertible {
    public let network: UInt32
    public let prefix: Int

    /// Largest network a scan may cover (a /22 is 1024 addresses).
    public static let widestPrefix = 22

    public init?(cidr: String) {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let base = Subnet.address(String(parts[0])), let bits = Int(parts[1]), (Subnet.widestPrefix...30).contains(bits) else { return nil }
        let mask = Subnet.mask(bits)
        guard base & ~mask == 0 else { return nil }
        network = base
        prefix = bits
    }

    public var description: String { "\(Subnet.text(network))/\(prefix)" }

    public func contains(_ ip: String) -> Bool {
        guard let value = Subnet.address(ip) else { return false }
        return value & Subnet.mask(prefix) == network
    }

    /// Only private (RFC 1918) networks may be scanned.
    public var isPrivate: Bool {
        let first = network >> 24, second = (network >> 16) & 0xFF
        return first == 10 || (first == 172 && (16...31).contains(second)) || (first == 192 && second == 168)
    }

    public static func address(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard part.count <= 3, part.allSatisfy(\.isNumber), let octet = UInt32(part), octet <= 255 else { return nil }
            value = value << 8 | octet
        }
        return value
    }

    public static func text(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String(value >> UInt32($0) & 0xFF) }.joined(separator: ".")
    }

    private static func mask(_ bits: Int) -> UInt32 {
        bits == 0 ? 0 : ~UInt32(0) << UInt32(32 - bits)
    }
}

public enum IPv4 {
    public static func isValid(_ text: String) -> Bool { Subnet.address(text) != nil }
}
