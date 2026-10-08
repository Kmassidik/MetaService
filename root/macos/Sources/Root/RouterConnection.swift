import CryptoKit
import Foundation
import Network
import RootCore

/// One TCP (or TLS) connection to a MikroTik's binary API. Not safe to share between tasks.
final class RouterConnection: @unchecked Sendable {
    private let connection: NWConnection
    private var decoder = RouterOSWire.Decoder()
    private static let maxChunk = 64 * 1024

    init(host: String, port: UInt16, tls: Bool, pinnedFingerprint: String?) {
        let parameters: NWParameters
        if tls {
            let options = NWProtocolTLS.Options()
            if let pin = pinnedFingerprint?.replacingOccurrences(of: ":", with: "").lowercased() {
                sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, trust, complete in
                    complete(Self.leafFingerprint(trust) == pin)
                }, DispatchQueue.global())
            }
            parameters = NWParameters(tls: options)
        } else {
            parameters = .tcp
        }
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
    }

    func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.first() { continuation.resume() }
                case .failed, .cancelled, .waiting: if once.first() { continuation.resume(throwing: RouterFailure.unreachable) }
                default: break
                }
            }
            connection.start(queue: DispatchQueue.global())
        }
    }

    func send(_ sentence: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: RouterOSWire.encode(sentence: sentence), completion: .contentProcessed { error in
                error == nil ? continuation.resume() : continuation.resume(throwing: RouterFailure.unreachable)
            })
        }
    }

    private var pending: [[String]] = []

    /// The next complete sentence, waiting for more bytes if needed.
    func nextSentence() async throws -> [String] {
        while pending.isEmpty { pending += try await receive() }
        return pending.removeFirst()
    }

    private func receive() async throws -> [[String]] {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxChunk) { data, _, isComplete, error in
                guard error == nil, let data, !data.isEmpty else { continuation.resume(throwing: RouterFailure.unreachable); return }
                continuation.resume(returning: data)
            }
        }
        do { return try decoder.feed(data) } catch { throw RouterFailure.badReply }
    }

    func close() { connection.cancel() }

    private static func leafFingerprint(_ trust: sec_trust_t) -> String? {
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first else { return nil }
        return SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func first() -> Bool { lock.lock(); defer { lock.unlock() }; defer { used = true }; return !used }
    }
}
