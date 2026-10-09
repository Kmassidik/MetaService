import Foundation

/// Reads the output of `arp -an` (macOS and Linux): lines like `? (192.168.100.1) at a:b:c:d:e:f on en0 ...`.
public enum ArpTable {
    private static let line = try! Regex(#"\((\d{1,3}(?:\.\d{1,3}){3})\)\s+at\s+([0-9A-Fa-f:\-]+)"#)

    public static func parse(_ output: String) -> [String: String] {
        var table: [String: String] = [:]
        for text in output.split(separator: "\n") {
            guard let match = text.firstMatch(of: line), let mac = MacAddress.normalize(String(match.output[2].substring ?? "")) else { continue }
            let ip = String(match.output[1].substring ?? "")
            guard Subnet.address(ip) != nil else { continue }
            table[ip] = mac
        }
        return table
    }
}
