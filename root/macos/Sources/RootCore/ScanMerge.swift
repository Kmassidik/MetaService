import Foundation

/// Combines what the router, nmap and the ARP table saw. Devices are matched by MAC address, else by IP.
public enum ScanMerge {
    public static func merge(router: [RouterEntry], nmap: [NmapHost], arp: [String: String], subnet: Subnet) -> [ScanFinding] {
        var byIp: [String: ScanFinding] = [:]
        for entry in router where subnet.contains(entry.ip) {
            add(&byIp, ip: entry.ip, mac: entry.mac, hostname: entry.hostname, vendor: nil, source: .router, agentPort: false)
        }
        for host in nmap where subnet.contains(host.ip) {
            add(&byIp, ip: host.ip, mac: host.mac, hostname: host.hostname, vendor: host.vendor, source: .nmap, agentPort: host.agentPortOpen)
        }
        for (ip, mac) in arp where subnet.contains(ip) && byIp[ip] != nil {
            add(&byIp, ip: ip, mac: mac, hostname: nil, vendor: nil, source: .arp, agentPort: false)
        }
        return dropMovedDuplicates(Array(byIp.values)).sorted { (Subnet.address($0.ip) ?? 0) < (Subnet.address($1.ip) ?? 0) }
    }

    private static func add(_ found: inout [String: ScanFinding], ip: String, mac: String?, hostname: String?, vendor: String?, source: ScanSource, agentPort: Bool) {
        var item = found[ip] ?? ScanFinding(ip: ip, mac: nil, hostname: nil, vendor: nil, seenBy: [], agentPortOpen: false)
        item.mac = item.mac ?? mac.flatMap(MacAddress.normalize)
        item.hostname = item.hostname ?? clean(hostname)
        item.vendor = item.vendor ?? clean(vendor)
        item.agentPortOpen = item.agentPortOpen || agentPort
        if !item.seenBy.contains(source) { item.seenBy.append(source) }
        found[ip] = item
    }

    /// The same MAC on two addresses (an old lease and a new one): keep the one that something really saw alive.
    private static func dropMovedDuplicates(_ items: [ScanFinding]) -> [ScanFinding] {
        var best: [String: ScanFinding] = [:]
        var loose: [ScanFinding] = []
        for item in items {
            guard let mac = item.mac else { loose.append(item); continue }
            guard let current = best[mac] else { best[mac] = item; continue }
            best[mac] = score(item) > score(current) ? item : current
        }
        return loose + Array(best.values)
    }

    private static func score(_ item: ScanFinding) -> Int {
        (item.seenBy.contains(.nmap) ? 2 : 0) + (item.seenBy.contains(.arp) ? 1 : 0)
    }

    private static let maxTextLength = 100

    /// Names come from devices on the network, so they are untrusted: trim, cap and drop control characters.
    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let printable = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespaces)
        return printable.isEmpty ? nil : String(printable.prefix(maxTextLength))
    }
}
