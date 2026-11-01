import Foundation
import MSCore

/// The opaque cursor of `GET /v1/security/events`. Grammar: `m1.<seconds>` where seconds is the Unix second up to which the log has been read
/// (digits only, so it is URL safe). Everything else, including a negative or oversize number, is "garbled".
public enum SecurityCursor {
    public static let prefix = "m1."
    /// 13 digits reach the year 318857; a longer number is not a time.
    static let maxDigits = 13

    public static func encode(_ seconds: Int) -> String { prefix + String(seconds) }

    /// nil for anything that is not exactly what `encode` writes.
    public static func decode(_ text: String) -> Int? {
        guard text.hasPrefix(prefix) else { return nil }
        let digits = text.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.count <= maxDigits, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return Int(digits)
    }
}

/// The query of the route: `after` (a cursor from an earlier answer) and `limit` (1...2000, default 500).
public struct SecurityQuery: Equatable {
    public static let defaultLimit = 500
    public static let limitRange = 1...2000
    public static let afterParameter = "after"
    public static let limitParameter = "limit"
    private static let tooOftenText = "each parameter may be given only once"
    private static let badLimitText = "limit must be a number from 1 to 2000"

    public let after: String?
    public let limit: Int

    public init(after: String? = nil, limit: Int = SecurityQuery.defaultLimit) {
        self.after = after
        self.limit = limit
    }

    /// `after` and `limit` are all the values the request gave for each parameter. A repeated parameter, or a limit that is not a number from 1 to 2000, is an input error.
    public static func parse(after: [String], limit: [String]) throws -> SecurityQuery {
        guard after.count <= 1, limit.count <= 1 else { throw InputError(tooOftenText) }
        let cursor = after.first.flatMap { $0.isEmpty ? nil : $0 }
        guard let given = limit.first else { return SecurityQuery(after: cursor) }
        guard let number = Int(given), limitRange.contains(number) else { throw InputError(badLimitText) }
        return SecurityQuery(after: cursor, limit: number)
    }
}
