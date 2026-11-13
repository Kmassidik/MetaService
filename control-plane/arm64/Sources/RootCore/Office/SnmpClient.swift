import Foundation

/// Failures of an SNMP exchange. Codec, agent and transport problems each have their own case.
public enum SnmpError: Error, Equatable {
    /// No reply arrived before the timeout.
    case timeout
    /// The reply bytes were malformed or outside the accepted shape. The reason is a short fixed text.
    case badResponse(String)
    /// The reply carried a different request id than the one sent.
    case mismatchedRequest
    /// The agent answered with a non-zero error status.
    case agentError(Int)
    /// The transport failed for a reason other than a timeout.
    case transportFailed(String)
}

/// Moves one encoded SNMP request to an agent and returns the raw reply bytes.
public protocol SnmpTransport: Sendable {
    /// Sends `request` and waits up to `timeout` seconds for one reply.
    func exchange(_ request: [UInt8], timeout: TimeInterval) async throws -> [UInt8]
}

/// Issues request ids 1, 2, 3 and so on, wrapping back to 1 after Int32.max. A lock keeps it safe to share.
final class SnmpRequestIds: @unchecked Sendable {
    private static let firstRequestId: Int32 = 1

    private let lock = NSLock()
    private var upcoming: Int32 = SnmpRequestIds.firstRequestId

    /// Returns the next request id.
    func next() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let issued = upcoming
        upcoming = issued == Int32.max ? SnmpRequestIds.firstRequestId : issued + 1
        return issued
    }
}

/// Reads SNMP values from one agent through a transport. Host-agnostic: the transport decides where bytes go.
public struct SnmpClient: Sendable {
    /// Seconds to wait for each reply.
    public static let defaultTimeout: TimeInterval = 2

    private let transport: any SnmpTransport
    private let community: String
    private let timeout: TimeInterval
    private let requestIds = SnmpRequestIds()

    /// Creates a client. `community` is sent with every request and must never be logged.
    public init(transport: any SnmpTransport, community: String, timeout: TimeInterval = SnmpClient.defaultTimeout) {
        self.transport = transport
        self.community = community
        self.timeout = timeout
    }

    /// Reads the given OIDs with GET. Returns one varbind per OID, in the order the agent answered.
    public func get(_ oids: [SnmpOid]) async throws -> [SnmpVarbind] {
        try await exchange(kind: .get, oids: oids)
    }

    /// Walks the subtree under `prefix` with GETNEXT. Stops at the end of the subtree, at endOfMibView, or after `maxEntries` (capped at `SnmpLimits.maxWalkEntries`).
    public func walk(_ prefix: SnmpOid, maxEntries: Int) async throws -> [SnmpVarbind] {
        let limit = min(max(maxEntries, 0), SnmpLimits.maxWalkEntries)
        var collected: [SnmpVarbind] = []
        var cursor = prefix
        while collected.count < limit {
            guard let next = try await nextVarbind(after: cursor, prefix: prefix) else {
                break
            }
            collected.append(next)
            cursor = next.oid
        }
        return collected
    }

    /// One GETNEXT step. Returns nil when the walk is over.
    private func nextVarbind(after cursor: SnmpOid, prefix: SnmpOid) async throws -> SnmpVarbind? {
        let answers = try await exchange(kind: .getNext, oids: [cursor])
        guard let answer = answers.first else {
            throw SnmpError.badResponse("GETNEXT answer had no varbind")
        }
        guard answer.value != .endOfMibView, answer.oid.hasPrefix(prefix) else {
            return nil
        }
        guard cursor.arcs.lexicographicallyPrecedes(answer.oid.arcs) else {
            throw SnmpError.badResponse("walk did not advance")
        }
        return answer
    }

    /// Sends one request and checks the reply: request id first, then error status.
    private func exchange(kind: SnmpPduKind, oids: [SnmpOid]) async throws -> [SnmpVarbind] {
        let requestId = requestIds.next()
        let request = SnmpV2c.encodeRequest(kind: kind, community: community, requestId: requestId, oids: oids)
        let reply = try await send(request)
        let response = try SnmpV2c.decodeResponse(reply)
        guard response.requestId == requestId else {
            throw SnmpError.mismatchedRequest
        }
        guard response.errorStatus == SnmpV2c.noErrorStatus else {
            throw SnmpError.agentError(response.errorStatus)
        }
        return response.varbinds
    }

    /// Hands the request to the transport. Transport errors keep their meaning; anything else becomes `transportFailed`.
    private func send(_ request: [UInt8]) async throws -> [UInt8] {
        do {
            return try await transport.exchange(request, timeout: timeout)
        } catch let error as SnmpError {
            throw error
        } catch {
            throw SnmpError.transportFailed(String(describing: error))
        }
    }
}
