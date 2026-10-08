import Foundation

/// Reads the JSON the MikroTik REST API (RouterOS 7) returns for `/ip/dhcp-server/lease` and `/ip/arp`.
public enum RouterOSRest {
    public static let leasePath = "/rest/ip/dhcp-server/lease"
    public static let arpPath = "/rest/ip/arp"
    private static let maxRows = 5000

    public static func leases(from json: Data) -> [RouterEntry] {
        rows(json).compactMap { row in
            guard row["disabled"] != "true", row["status"] == nil || row["status"] == "bound", let ip = row["address"], Subnet.address(ip) != nil else { return nil }
            return RouterEntry(ip: ip, mac: row["mac-address"].flatMap(MacAddress.normalize), hostname: row["host-name"] ?? row["comment"])
        }
    }

    public static func arp(from json: Data) -> [RouterEntry] {
        rows(json).compactMap { row in
            guard row["disabled"] != "true", row["complete"] != "false", let ip = row["address"], Subnet.address(ip) != nil else { return nil }
            return RouterEntry(ip: ip, mac: row["mac-address"].flatMap(MacAddress.normalize), hostname: nil)
        }
    }

    /// RouterOS sends every value as a string, and a list of objects. Anything else is an empty list.
    private static func rows(_ json: Data) -> [[String: String]] {
        guard let list = try? JSONSerialization.jsonObject(with: json) as? [Any] else { return [] }
        return list.prefix(maxRows).compactMap { item in
            (item as? [String: Any])?.compactMapValues { $0 as? String }
        }
    }
}
