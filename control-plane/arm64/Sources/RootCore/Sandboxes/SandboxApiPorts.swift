import Foundation

/// `POST /v2/sandboxes/{sandboxID}/ports`: the one field is the port to open.
public struct SandboxApiPortBody: Equatable, Sendable {
    public let port: Int

    public init(port: Int) {
        self.port = port
    }

    public static func parse(_ body: Data) throws -> SandboxApiPortBody {
        guard let json = try? JSONSerialization.jsonObject(with: body), let object = json as? [String: Any] else {
            throw SandboxApiFailure.invalid("The body must be a JSON object with a port.")
        }
        guard object.keys.allSatisfy({ $0 == "port" }) else { throw SandboxApiFailure.invalid("The body holds port only.") }
        guard let number = object["port"] as? NSNumber, number.doubleValue == number.doubleValue.rounded(),
              let port = Int(exactly: number), PortToken.portRange.contains(port) else {
            throw SandboxApiFailure.invalid("port must be a whole number from \(PortToken.portRange.lowerBound) to \(PortToken.portRange.upperBound).")
        }
        return SandboxApiPortBody(port: port)
    }
}

/// The answer to an expose: where to reach the port and the token to carry. The token is the one secret here: it is never
/// logged and never written down, and the host alone is useless without it.
public struct SandboxApiPort: Encodable, Equatable {
    public let host: String
    public let token: String
    public let expiresAt: String

    public init(host: String, token: String, expiresAt: String) {
        self.host = host
        self.token = token
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey { case host, token, expiresAt }
}
