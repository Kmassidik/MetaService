import Foundation
import MSCore
import RootCore
import RootStore

/// Reads a machine's storage map from its helper, or asks the helper to start a scan. Nothing is kept here: the helper holds the last scan, and each request asks it again.
final class StorageService: Sendable {
    static let helperTimeoutSeconds: TimeInterval = 10
    /// Scan requests per machine in a minute, however many tabs or clicks ask. The helper itself starts no new scan within 30 seconds of the last one.
    static let scansPerMinute = 6
    private static let missingRouteStatus = 404
    private static let mapPath = "/v1/storage"
    private static let scanPath = "/v1/storage/scan"

    private let machines: MachineStore
    private let client: AgentClient
    private let throttle: Throttle
    private let clock: Clock

    init(machines: MachineStore, client: AgentClient, throttle: Throttle, clock: Clock) {
        self.machines = machines
        self.client = client
        self.throttle = throttle
        self.clock = clock
    }

    /// The envelope with the last finished scan. Throws `MachineError.notFound` for a machine that does not exist. Never starts a scan.
    func reply(for id: String) async throws -> StorageReply {
        let summary = try machines.get(id: id, now: clock.now)
        guard summary.state != "offline" else { return .make(.unreachable) }
        return .make(await ask(id, method: "GET", path: Self.mapPath, expecting: 200))
    }

    /// Asks the helper to scan and answers with the same envelope. Throws `MachineError.notFound` for a machine that does not exist, and `ApiFailure.tooMany` past the per-machine limit.
    func scan(for id: String) async throws -> StorageReply {
        let summary = try machines.get(id: id, now: clock.now)
        guard summary.state != "offline" else { return .make(.unreachable) }
        guard throttle.allow("storage-scan:\(id)", limit: Self.scansPerMinute, seconds: 60) else { throw ApiFailure.tooMany }
        return .make(await ask(id, method: "POST", path: Self.scanPath, expecting: 202))
    }

    private func ask(_ id: String, method: String, path: String, expecting status: Int) async -> ReadingOutcome<Storage> {
        guard let reply = try? await client.call(machine: id, method: method, path: path, timeout: Self.helperTimeoutSeconds, maxBytes: Storage.maxAnswerBytes) else { return .unreachable }
        guard reply.status != Self.missingRouteStatus else { return .oldHelper }
        guard reply.status == status, let storage = try? Storage.parse(reply.data) else { return .unreachable }
        return .fresh(storage)
    }
}
