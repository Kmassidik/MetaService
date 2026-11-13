import Foundation

/// The values needed to read the router, once the settings say it is configured. The community is a secret: it is only sent to the transport and never printed.
public struct OfficeSnmpTarget: Equatable, Sendable {
    public let host: String
    public let community: String
    public let wanIndexes: [Int]
    public let intervalSeconds: Int

    public init(host: String, community: String, wanIndexes: [Int], intervalSeconds: Int) {
        self.host = host
        self.community = community
        self.wanIndexes = wanIndexes
        self.intervalSeconds = intervalSeconds
    }
}

/// The router settings read from the environment. Configured means a host, a community and at least one WAN index are all set.
/// Bad values are skipped (host, WAN indexes) or refused (interval), so a typo never looks like "not configured" by accident.
public struct OfficeSnmpSettings: Equatable, Sendable, CustomStringConvertible {
    public static let hostKey = "OFFICE_SNMP_HOST"
    public static let communityKey = "OFFICE_SNMP_COMMUNITY"
    public static let wanIndexesKey = "OFFICE_SNMP_WAN_INDEXES"
    public static let intervalKey = "OFFICE_SNMP_INTERVAL_SECONDS"

    /// The interval is the one setting a bad value is refused for. Only the message is kept, so nothing from the input is echoed.
    public struct Refused: Error, Equatable, Sendable {
        public let message = "OFFICE_SNMP_INTERVAL_SECONDS must be a whole number from 10 to 600"
    }

    public static let disabled = OfficeSnmpSettings(host: nil, community: nil, wanIndexes: [], intervalSeconds: OfficeRules.defaultIntervalSeconds)

    /// An IPv4 address as text, or nil when not set.
    public let host: String?
    /// The SNMP community. Secret: never logged, never in an answer.
    public let community: String?
    public let wanIndexes: [Int]
    public let intervalSeconds: Int

    public init(host: String?, community: String?, wanIndexes: [Int], intervalSeconds: Int) {
        self.host = host
        self.community = community
        self.wanIndexes = wanIndexes
        self.intervalSeconds = intervalSeconds
    }

    /// The target to read, or nil when the router is not configured.
    public var target: OfficeSnmpTarget? {
        guard let host, let community, !wanIndexes.isEmpty else { return nil }
        return OfficeSnmpTarget(host: host, community: community, wanIndexes: wanIndexes, intervalSeconds: intervalSeconds)
    }

    /// Shows whether a community is set, never its value.
    public var description: String {
        "OfficeSnmpSettings(host: \(host ?? "not set"), wanIndexes: \(wanIndexes), intervalSeconds: \(intervalSeconds), community: \(community == nil ? "not set" : "set"))"
    }

    /// Reads the four settings from an environment map. Blank values are already removed by the caller, so a missing key means not set.
    public static func parse(_ env: [String: String]) throws -> OfficeSnmpSettings {
        OfficeSnmpSettings(host: env[hostKey].flatMap(ipv4Host), community: env[communityKey], wanIndexes: parseWanIndexes(env[wanIndexesKey]),
                           intervalSeconds: try parseInterval(env[intervalKey]))
    }

    /// The host when it is IPv4 text, otherwise nil (host names and IPv6 count as not set).
    static func ipv4Host(_ text: String) -> String? {
        IPv4.isValid(text) ? text : nil
    }

    /// Comma-separated positive whole numbers, duplicates removed, at most `OfficeRules.maxWanIndexes`. Anything bad is skipped.
    static func parseWanIndexes(_ text: String?) -> [Int] {
        guard let text else { return [] }
        var unique: [Int] = []
        for index in text.split(separator: ",").compactMap({ parseWanIndex(String($0)) }) where !unique.contains(index) {
            unique.append(index)
        }
        return Array(unique.prefix(OfficeRules.maxWanIndexes))
    }

    /// One positive interface index, or nil when the text is not one.
    static func parseWanIndex(_ text: String) -> Int? {
        guard let value = UInt32(text.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return Int(value)
    }

    /// The polling interval: the default when unset, otherwise a whole number inside the allowed range.
    static func parseInterval(_ text: String?) throws -> Int {
        guard let text else { return OfficeRules.defaultIntervalSeconds }
        let range = OfficeRules.minIntervalSeconds...OfficeRules.maxIntervalSeconds
        guard let value = Int(text), range.contains(value) else { throw Refused() }
        return value
    }
}
