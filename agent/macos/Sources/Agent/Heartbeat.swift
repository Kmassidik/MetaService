import Foundation
import AgentCore

/// Tells the Root, every few seconds, what this machine is and what runs on it. It also speaks up at once after a change.
/// A failure is logged once and retried more slowly.
final class Heartbeat: @unchecked Sendable {
    private let root: URL
    private let token: String
    private let service: AgentService
    private let agentPort: Int
    private let seconds: Int
    private let lock = NSLock()
    private var soon = false
    private static let slowSeconds = 60
    private static let tick: UInt64 = 250_000_000

    init(root: URL, token: String, service: AgentService, agentPort: Int, seconds: Int) {
        self.root = root
        self.token = token
        self.service = service
        self.agentPort = agentPort
        self.seconds = seconds
    }

    /// Ask for a heartbeat now instead of at the next interval.
    func beatSoon() {
        lock.lock(); defer { lock.unlock() }
        soon = true
    }

    func run() async {
        var failing = false
        while !Task.isCancelled {
            let ok = await beat()
            if !ok && !failing { log("cannot reach the Root; will keep trying") }
            if ok && failing { log("the Root is reachable again") }
            failing = !ok
            await rest(ok ? seconds : Self.slowSeconds)
        }
    }

    private func rest(_ interval: Int) async {
        var waited: UInt64 = 0
        while waited < UInt64(interval) * 1_000_000_000 {
            try? await Task.sleep(nanoseconds: Self.tick)
            waited += Self.tick
            guard !takeSoon() else { return }
        }
    }

    private func takeSoon() -> Bool {
        lock.lock(); defer { lock.unlock() }
        defer { soon = false }
        return soon
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
        return try Json.encoder.encode(Report(facts: facts, workloads: workloads, bundleVersion: await service.health().bundleVersion, agentPort: agentPort))
    }

    private func log(_ text: String) {
        FileHandle.standardError.write(Data("metaservice-agent: \(text)\n".utf8))
    }
}

private struct Report: Encodable {
    let facts: Facts
    let workloads: [Workload]
    let bundleVersion: String?
    let agentPort: Int
}
