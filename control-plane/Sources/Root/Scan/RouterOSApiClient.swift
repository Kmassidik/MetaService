import CryptoKit
import Foundation
import RootCore

/// Reads DHCP leases and the ARP table through the MikroTik binary API (RouterOS 6, and 7 if REST is off).
/// Use api-ssl with a pinned certificate where you can: the plain api port sends the password unencrypted.
final class RouterOSApiClient: RouterReader, @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let tls: Bool
    private let user: String
    private let password: String
    private let pin: String?
    private static let overallSeconds: UInt64 = 15
    private static let maxRows = 5000

    init?(config: RootConfig) {
        guard let text = config.routerURL, let url = URL(string: text), let host = url.host, let user = config.routerUser, let password = config.routerPassword else { return nil }
        self.host = host
        tls = url.scheme == "api-ssl"
        port = UInt16(url.port ?? (tls ? 8729 : 8728))
        self.user = user
        self.password = password
        pin = config.routerCertSha256
    }

    func entries() async throws -> [RouterEntry] {
        try await withThrowingTaskGroup(of: [RouterEntry].self) { group in
            group.addTask { try await self.read() }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.overallSeconds * 1_000_000_000)
                throw RouterFailure.unreachable
            }
            defer { group.cancelAll() }
            return try await group.next() ?? []
        }
    }

    private func read() async throws -> [RouterEntry] {
        let connection = RouterConnection(host: host, port: port, tls: tls, pinnedFingerprint: pin)
        try await connection.open()
        defer { connection.close() }
        try await login(connection)
        let leases = RouterOSRows.leases(try await rows(connection, "/ip/dhcp-server/lease/print"))
        let arp = RouterOSRows.arp(try await rows(connection, "/ip/arp/print"))
        return leases + arp
    }

    /// RouterOS 6.43 and later take the password directly; older ones answer with a challenge first.
    private func login(_ connection: RouterConnection) async throws {
        try await connection.send(["/login", "=name=\(user)", "=password=\(password)"])
        let first = try await reply(connection)
        guard let challenge = first.attributes["ret"] else { return try check(first) }
        try await connection.send(["/login", "=name=\(user)", "=response=00" + Self.response(challenge: challenge, password: password)])
        try check(try await reply(connection))
    }

    private static func response(challenge: String, password: String) -> String {
        let bytes = stride(from: 0, to: challenge.count - 1, by: 2).compactMap { index -> UInt8? in
            let start = challenge.index(challenge.startIndex, offsetBy: index)
            return UInt8(challenge[start..<challenge.index(start, offsetBy: 2)], radix: 16)
        }
        let digest = Insecure.MD5.hash(data: Data([0]) + Data(password.utf8) + Data(bytes))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func rows(_ connection: RouterConnection, _ command: String) async throws -> [[String: String]] {
        try await connection.send([command])
        var found: [[String: String]] = []
        while true {
            let answer = try await reply(connection)
            guard answer.kind != "!done" else { return found }
            guard answer.kind == "!re" else { throw RouterFailure.refused(0) }
            if found.count < Self.maxRows { found.append(answer.attributes) }
        }
    }

    private struct Reply {
        let kind: String
        let attributes: [String: String]
    }

    private func reply(_ connection: RouterConnection) async throws -> Reply {
        let sentence = try await connection.nextSentence()
        return Reply(kind: sentence.first ?? "", attributes: RouterOSWire.attributes(of: sentence))
    }

    private func check(_ answer: Reply) throws {
        guard answer.kind == "!done" else { throw RouterFailure.refused(401) }
    }
}
