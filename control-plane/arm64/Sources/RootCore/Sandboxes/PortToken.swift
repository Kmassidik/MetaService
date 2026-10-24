import Foundation
import MSCore

/// The short-lived token that travels with every request to a port host, so a leaked link (a log, a screenshot, a chat
/// message) is not a door: it proves the caller was given this host, and it stops working after `lifetimeSeconds`.
///
/// The token is HMAC-signed with the Root's own key over (label, sandbox, port, expiry). The key itself never comes in here:
/// the caller passes a function that signs a subject with `SecretBox.signature(subject:purpose:)`, exactly as `PortHosts`
/// takes the label's signature. Nothing about the token is stored.
///
/// Shape, with `.` between the parts:
///
///     v1.<label>.<expiry>.<sandbox>.<port>.<mac>
///
/// `expiry` is Unix seconds; `mac` is the first `macCharacters` of the signature, 128 bits, so the text stays small and
/// fits a URL. It travels in `?token=` or the `X-Port-Token` header, and is never logged.
public enum PortToken {
    /// The purpose the token's signature is derived under, apart from the label's, so the two can never be swapped.
    public static let purpose = "sandbox-port-token"
    public static let version = "v1"
    /// Fifteen minutes: long enough for a page and its assets, short enough that a leaked link dies by itself.
    public static let lifetimeSeconds = 15 * 60
    /// One query parameter and one header, whichever the caller finds easier. Both is fine when they agree.
    public static let queryName = "token"
    public static let headerName = "X-Port-Token"
    /// Hex characters of the signature kept as the token's mac: 128 bits.
    public static let macCharacters = 32
    /// Nothing longer than this is even looked at, so a huge string costs nothing.
    public static let maxLength = 200
    public static let portRange = 1...65535
    private static let parts = 6
    private static let hexCharacters = Set("0123456789abcdef")

    public struct Claims: Equatable, Sendable {
        public let label: String
        public let sandbox: String
        public let port: Int
        public let expiresAt: Date

        public init(label: String, sandbox: String, port: Int, expiresAt: Date) {
            self.label = label
            self.sandbox = sandbox
            self.port = port
            self.expiresAt = expiresAt
        }
    }

    public struct Issued: Equatable, Sendable {
        public let token: String
        public let expiresAt: Date

        public init(token: String, expiresAt: Date) {
            self.token = token
            self.expiresAt = expiresAt
        }
    }

    public enum Refusal: Error, Equatable, Sendable {
        /// The token was ours but its time is up. The caller is asked for a fresh one, not for a key.
        case expired
        /// A token for another host: it was not given out for this label.
        case wrongLabel
        /// Not one of our tokens, or one whose text was changed.
        case malformed
    }

    // MARK: issuing

    /// The moment a token issued now stops working. `issue` works it out the same way, so a caller can sign the subject
    /// before it calls `issue`.
    public static func expiry(now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(lifetimeSeconds))
    }

    /// What the Root signs for one token: the label, the sandbox, the port and the expiry, so a token cannot be moved to
    /// another host, another port or a later time.
    public static func subject(label: String, sandbox: String, port: Int, expiresAt: Date) -> String {
        "\(version):\(label):\(sandbox):\(port):\(seconds(expiresAt))"
    }

    /// The token for one host, or nil when the parts are not ours or the signature is not the lowercase hex this expects.
    public static func issue(sandbox: String, port: Int, label: String, now: Date, lifetimeSignature: String) -> Issued? {
        guard PortHosts.isLabel(label), portRange.contains(port), !sandbox.isEmpty,
              let mac = hex(from: lifetimeSignature, characters: macCharacters) else { return nil }
        let expiresAt = expiry(now: now)
        let token = [version, label, String(seconds(expiresAt)), sandbox, String(port), mac].joined(separator: ".")
        guard token.count <= maxLength else { return nil }
        return Issued(token: token, expiresAt: expiresAt)
    }

    // MARK: checking

    /// The claims a token holds, when its signature is ours and it has not expired. `signature` is asked for the subject this
    /// token claims, so the Root's key stays outside this file.
    public static func verify(token: String, label: String, now: Date,
                              signature: (String) -> String) -> Result<Claims, Refusal> {
        guard let (claims, mac) = try? parse(token) else { return .failure(.malformed) }
        guard claims.label == label else { return .failure(.wrongLabel) }
        guard claims.expiresAt > now else { return .failure(.expired) }
        let signed = signature(subject(label: claims.label, sandbox: claims.sandbox, port: claims.port, expiresAt: claims.expiresAt))
        guard let expected = hex(from: signed, characters: macCharacters), Tokens.constantTimeEqual(expected, mac) else {
            return .failure(.malformed)
        }
        return .success(claims)
    }

    /// The token as a request carries it: `?token=` or `X-Port-Token`. Nil when neither is given, and also when both are
    /// given and disagree, because a request may not offer two answers.
    public static func presented(query: String?, header: String?) -> String? {
        let fromQuery = token(inQuery: query)
        guard let header, !header.isEmpty else { return fromQuery }
        guard let fromQuery else { return header }
        return Tokens.constantTimeEqual(fromQuery, header) ? fromQuery : nil
    }

    // MARK: pieces

    private static func parse(_ token: String) throws -> (Claims, String) {
        guard token.count <= maxLength else { throw Refusal.malformed }
        let fields = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == parts, fields[0] == version,
              let expiry = Int(fields[2]), expiry > 0,
              let port = Int(fields[4]), portRange.contains(port),
              PortHosts.isLabel(fields[1]), !fields[3].isEmpty,
              let mac = hex(from: fields[5], characters: macCharacters), mac == fields[5] else {
            throw Refusal.malformed
        }
        let claims = Claims(label: fields[1], sandbox: fields[3], port: port,
                            expiresAt: Date(timeIntervalSince1970: TimeInterval(expiry)))
        return (claims, mac)
    }

    /// The token parameter of a query string, if it is there. Kept here so the query rule lives next to the token it names.
    static func token(inQuery query: String?) -> String? {
        query?.split(separator: "&").compactMap { pair -> String? in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.first == Substring(queryName) else { return nil }
            return parts.count == 2 ? String(parts[1]) : ""
        }.first.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The first `characters` of a signature, when the text holds that many lowercase hex characters.
    private static func hex(from signature: String, characters: Int) -> String? {
        guard signature.count >= characters else { return nil }
        let text = String(signature.prefix(characters))
        return text.allSatisfy(hexCharacters.contains) ? text : nil
    }

    private static func seconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970)
    }
}
