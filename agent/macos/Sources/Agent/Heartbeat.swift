import Foundation
import AgentCore

/// Tells the Root, every 15 seconds, what this machine is and what runs on it. A failure is logged once and retried.
final class Heartbeat: @unchecked Sendable {
    private let root: URL
    private let token: String
    private let service: AgentService
    private static let interval: TimeInterval = 15
    private static let slowInterval: TimeInterval = 60

    init(root: URL, token: String, service: AgentService) {
        self.root = root
        self.token = token
        self.service = service
    }

    func run() async {
        var failing = false
        while !Task.isCancelled {
            let ok = await beat()
            if !ok && !failing { log("cannot reach the Root; will keep trying") }
            if ok && failing { log("the Root is reachable again") }
            failing = !ok
            try? await Task.sleep(nanoseconds: UInt64((ok ? Self.interval : Self.slowInterval) * 1_000_000_000))
        }
    }

    private func beat() async -> Bool {
        do {
            var request = URLRequest(url: root.appendingPathComponent("v1/agents/heartbeat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try await body()
            let (_, response) = try await RootLink.session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 204
        } catch {
            return false
        }
    }

    private func body() async throws -> Data {
        let facts = try await service.facts()
        let workloads = try await service.workloads()
        return try Json.encoder.encode(Report(facts: facts, workloads: workloads, bundleVersion: await service.health().bundleVersion))
    }

    private func log(_ text: String) {
        FileHandle.standardError.write(Data("metaservice-agent: \(text)\n".utf8))
    }
}

private struct Report: Encodable {
    let facts: Facts
    let workloads: [Workload]
    let bundleVersion: String?
}
