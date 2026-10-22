import Foundation

/// The optional `points` query of `GET /api/machines/{id}/stats/history`: how many of the newest points to send, 1 to 360, default 360.
public enum HistoryQuery {
    public struct Refused: Error, Equatable, Sendable {
        public let message = "points must be a whole number from 1 to \(StatsHistory.capacity)"
    }

    public static let parameter = "points"

    /// `values` are all the `points` parameters of the request, in order. Only plain digits count ("+5", " 5", "05" and "5.0" are refused).
    public static func points(values: [String]) throws -> Int {
        guard !values.isEmpty else { return StatsHistory.capacity }
        guard values.count == 1, let only = values.first, let count = plainNumber(only), (1...StatsHistory.capacity).contains(count) else { throw Refused() }
        return count
    }

    private static func plainNumber(_ text: String) -> Int? {
        guard !text.isEmpty, text.count <= 3, text.first != "0", text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}

/// The answer of the history route: the gap between points (10 seconds, shorter only when a test asks for it) and the points, oldest first.
public struct HistoryReply: Encodable, Equatable, Sendable {
    public let intervalSeconds: Int
    public let points: [HistoryPoint]

    public init(intervalSeconds: Int, points: [HistoryPoint]) {
        self.intervalSeconds = intervalSeconds
        self.points = points
    }
}
