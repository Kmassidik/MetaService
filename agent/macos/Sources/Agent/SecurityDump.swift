import Foundation
import AgentCore

/// `metaservice-agent security-dump`: prints what the security route would answer (baseline; events are always empty on macOS) for this Mac, read only.
enum SecurityDump {
    static func run(hours: Int) async throws {
        let service = SecurityHost.makeService()
        await service.refreshPendingUpdates()
        let answer = try await service.answer(SecurityQuery(limit: SecurityQuery.limitRange.upperBound))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(answer), as: UTF8.self))
    }
}
