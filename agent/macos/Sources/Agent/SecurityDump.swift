import Foundation
import AgentCore

/// `metaservice-agent security-dump [--hours N]`: prints what the security route would answer on a first call (events plus baseline) for this Mac, read only.
enum SecurityDump {
    /// A dump may take as long as the log needs.
    static let budgetSeconds: TimeInterval = 3600
    private static let secondsPerHour = 3600

    static func run(hours: Int) async throws {
        let service = SecurityHost.makeService(budget: budgetSeconds, history: hours * secondsPerHour)
        await service.refreshPendingUpdates()
        let answer = try await service.answer(SecurityQuery(limit: SecurityQuery.limitRange.upperBound))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(answer), as: UTF8.self))
    }
}
