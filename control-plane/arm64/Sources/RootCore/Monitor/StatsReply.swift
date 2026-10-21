import Foundation

/// The envelope the panel reads from `GET /api/machines/{id}/stats`. Missing numbers are written as null, never left out and never 0.
public struct StatsReply<Value: Encodable & Sendable>: Encodable, Sendable {
    public let state: String
    public let lastSeen: String?
    public let fetchedAt: String?
    public let stats: Value?

    public static func make(machineOffline: Bool, lastSeen: String?, reading: Reading<Value>) -> StatsReply {
        StatsReply(state: Self.state(machineOffline: machineOffline, kind: reading.answer), lastSeen: lastSeen, fetchedAt: reading.fetchedAt.map(Self.iso), stats: reading.value)
    }

    private static func state(machineOffline: Bool, kind: ReadingKind) -> String {
        guard !machineOffline else { return "offline" }
        switch kind {
        case .fresh: return "online"
        case .oldHelper: return "old_helper"
        case .unreachable: return "offline"
        }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private enum CodingKeys: String, CodingKey { case state, lastSeen, fetchedAt, stats }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(state, forKey: .state)
        try box.encode(lastSeen, forKey: .lastSeen)
        try box.encode(fetchedAt, forKey: .fetchedAt)
        try box.encode(stats, forKey: .stats)
    }
}
