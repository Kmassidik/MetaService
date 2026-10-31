import Foundation

/// The query of the two Security routes. Anything unknown, repeated, empty or out of range is refused with a plain message (a 400).
public struct SecurityQuery: Equatable, Sendable {
    public struct Refused: Error, Equatable, Sendable {
        public let message: String
    }

    public static let maxPageSize = 100
    public static let defaultPageSize = 25
    public static let maxPage = 1_000_000
    public static let maxText = 64
    private static let maxMachineLength = 63
    private static let machinePattern = #/^[a-z0-9][a-z0-9-]*$/#
    private static let overviewNames: Set<String> = ["range"]
    private static let eventsNames: Set<String> = ["range", "machine", "type", "q", "page", "page_size"]

    public var range = SecurityRange.standard
    /// Empty means any.
    public var machine = ""
    public var type: SecurityEventType?
    /// Part of an address or user name; empty means any.
    public var text = ""
    public var page = 1
    public var pageSize = SecurityQuery.defaultPageSize

    public init() {}

    public var offset: Int { (page - 1) * pageSize }

    public static func overview(_ pairs: [(String, String)]) throws -> SecurityRange {
        try SecurityQuery.read(pairs, allowed: overviewNames).range
    }

    public static func events(_ pairs: [(String, String)]) throws -> SecurityQuery {
        try read(pairs, allowed: eventsNames)
    }

    private static func read(_ pairs: [(String, String)], allowed: Set<String>) throws -> SecurityQuery {
        var query = SecurityQuery()
        var seen = Set<String>()
        for (name, value) in pairs {
            guard allowed.contains(name) else { throw Refused(message: "unknown parameter \(name)") }
            guard seen.insert(name).inserted else { throw Refused(message: "\(name) was sent more than once") }
            try query.set(name, value)
        }
        return query
    }

    private mutating func set(_ name: String, _ value: String) throws {
        switch name {
        case "range": range = try Self.choice(value, SecurityRange(rawValue: value), name)
        case "machine": machine = try Self.machineId(value)
        case "type": type = try Self.choice(value, SecurityEventType(rawValue: value), name)
        case "q": text = try Self.search(value)
        case "page": page = try Self.number(value, name, 1...Self.maxPage)
        default: pageSize = try Self.number(value, name, 1...Self.maxPageSize)
        }
    }

    private static func choice<T>(_ value: String, _ found: T?, _ name: String) throws -> T {
        guard let found else { throw Refused(message: "\(name) is not one of the allowed values") }
        return found
    }

    private static func machineId(_ value: String) throws -> String {
        guard value.count <= maxMachineLength, (try? machinePattern.wholeMatch(in: value)) != nil else { throw Refused(message: "machine is not a machine id") }
        return value
    }

    /// Spaces at both ends are dropped; control characters and anything longer than 64 characters are refused.
    private static func search(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count <= maxText, !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw Refused(message: "q must be plain text of at most \(maxText) characters")
        }
        return trimmed
    }

    /// Plain digits only ("+5", " 5", "05" and "5.0" are refused).
    private static func number(_ value: String, _ name: String, _ allowed: ClosedRange<Int>) throws -> Int {
        guard value.first != "0", value.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(value), allowed.contains(number) else {
            throw Refused(message: "\(name) must be a whole number from \(allowed.lowerBound) to \(allowed.upperBound)")
        }
        return number
    }
}
