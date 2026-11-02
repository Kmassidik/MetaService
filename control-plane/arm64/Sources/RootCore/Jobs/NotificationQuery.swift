import Foundation

/// The query of GET /api/notifications and the body of POST /api/notifications/read. Anything unknown, repeated or out of range is refused with a plain message (a 400).
public struct NotificationQuery: Equatable, Sendable {
    public struct Refused: Error, Equatable, Sendable {
        public let message: String
    }

    public static let maxPageSize = 100
    public static let defaultPageSize = 25
    public static let maxPage = 1_000_000
    private static let allowed: Set<String> = ["page", "page_size", "unread"]

    public var page = 1
    public var pageSize = NotificationQuery.defaultPageSize
    public var unreadOnly = false

    public init() {}

    public static func read(_ pairs: [(String, String)]) throws -> NotificationQuery {
        var query = NotificationQuery()
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
        case "page": page = try Self.number(value, name, 1...Self.maxPage)
        case "page_size": pageSize = try Self.number(value, name, 1...Self.maxPageSize)
        default: unreadOnly = try Self.flag(value, name)
        }
    }

    private static func flag(_ value: String, _ name: String) throws -> Bool {
        switch value {
        case "true": return true
        case "false": return false
        default: throw Refused(message: "\(name) must be true or false")
        }
    }

    /// Plain digits only ("+5", " 5", "05" and "5.0" are refused).
    private static func number(_ value: String, _ name: String, _ allowed: ClosedRange<Int>) throws -> Int {
        guard value.first != "0", value.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(value), allowed.contains(number) else {
            throw Refused(message: "\(name) must be a whole number from \(allowed.lowerBound) to \(allowed.upperBound)")
        }
        return number
    }
}

/// Which notifications to mark read: a short list of ids, or all of the user's.
public enum NotificationMark: Equatable, Sendable {
    case ids([Int])
    case all

    public static let maxIds = 100

    /// Exactly one of `ids` (1 to 100 positive whole numbers) or `all: true`.
    public static func parse(_ data: Data) throws -> NotificationMark {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any], Set(body.keys).isSubset(of: ["ids", "all"]), body.count == 1 else {
            throw NotificationQuery.Refused(message: "send exactly one of ids or all")
        }
        if let all = body["all"] {
            guard (all as? Bool) == true else { throw NotificationQuery.Refused(message: "all must be true") }
            return .all
        }
        guard let ids = body["ids"] as? [Int], (1...maxIds).contains(ids.count), ids.allSatisfy({ $0 >= 1 }) else {
            throw NotificationQuery.Refused(message: "ids must be 1 to \(maxIds) whole numbers above zero")
        }
        return .ids(ids)
    }
}
