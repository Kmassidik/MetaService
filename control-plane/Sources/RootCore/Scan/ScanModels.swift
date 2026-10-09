import Foundation

public enum ScanSource: String, Codable, CaseIterable {
    case router, nmap, arp
}

/// One device as the MikroTik sees it (a DHCP lease or an ARP entry).
public struct RouterEntry: Equatable {
    public let ip: String
    public let mac: String?
    public let hostname: String?

    public init(ip: String, mac: String?, hostname: String?) {
        self.ip = ip
        self.mac = mac
        self.hostname = hostname
    }
}

/// One live address as nmap saw it.
public struct NmapHost: Equatable {
    public let ip: String
    public let mac: String?
    public let vendor: String?
    public let hostname: String?
    public let agentPortOpen: Bool

    public init(ip: String, mac: String?, vendor: String?, hostname: String?, agentPortOpen: Bool = false) {
        self.ip = ip
        self.mac = mac
        self.vendor = vendor
        self.hostname = hostname
        self.agentPortOpen = agentPortOpen
    }
}

/// A merged result: one row per device, with where it was seen.
public struct ScanFinding: Equatable, Codable {
    public var ip: String
    public var mac: String?
    public var hostname: String?
    public var vendor: String?
    public var seenBy: [ScanSource]
    public var agentPortOpen: Bool

    public init(ip: String, mac: String?, hostname: String?, vendor: String?, seenBy: [ScanSource], agentPortOpen: Bool) {
        self.ip = ip
        self.mac = mac
        self.hostname = hostname
        self.vendor = vendor
        self.seenBy = seenBy
        self.agentPortOpen = agentPortOpen
    }
}
