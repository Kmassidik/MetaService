import CryptoKit
import Foundation
import RootCore

/// Reads DHCP leases and the ARP table from a MikroTik with its REST API (RouterOS 7), using a read-only account.
/// An https router with its own certificate is trusted only if the certificate fingerprint in ROUTER_CERT_SHA256 matches.
final class RouterOSClient: RouterReader, @unchecked Sendable {
    private let base: URL
    private let authorization: String
    private let session: URLSession
    private static let maxReplyBytes = 2 * 1024 * 1024
    private static let requestSeconds: TimeInterval = 10

    init?(config: RootConfig) {
        guard let text = config.routerURL, let url = URL(string: text), let user = config.routerUser, let password = config.routerPassword else { return nil }
        base = url
        authorization = "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = Self.requestSeconds
        options.httpCookieStorage = nil
        options.urlCache = nil
        session = URLSession(configuration: options, delegate: Pinning(fingerprint: config.routerCertSha256), delegateQueue: nil)
    }

    func entries() async throws -> [RouterEntry] {
        let leases = RouterOSRest.leases(from: try await get(RouterOSRest.leasePath))
        let arp = RouterOSRest.arp(from: try await get(RouterOSRest.arpPath))
        return leases + arp
    }

    private func get(_ path: String) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { throw RouterFailure.unreachable }
        guard http.statusCode == 200 else { throw RouterFailure.refused(http.statusCode) }
        guard data.count <= Self.maxReplyBytes else { throw RouterFailure.badReply }
        return data
    }

    private final class Pinning: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
        let fingerprint: String?

        init(fingerprint: String?) { self.fingerprint = fingerprint }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            guard let fingerprint, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust,
                  let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
                return (.performDefaultHandling, nil)
            }
            let seen = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
            return seen == fingerprint.replacingOccurrences(of: ":", with: "") ? (.useCredential, URLCredential(trust: trust)) : (.cancelAuthenticationChallenge, nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
