import Foundation

public enum WireGuardError: Error, Equatable {
    case badKey(String)
    case noFreeAddress
    case badPort
}

/// The private network of the hub-and-spoke: the parent is `.1`, each machine gets the next free address. Default 10.99.0.0/24 (up to 253 machines).
public struct WireGuardNetwork: Equatable, Sendable {
    public let prefix: String
    public let hostAddress = 1
    public static let standard = WireGuardNetwork(prefix: "10.99.0")
    public static let listenPort = 51820
    private static let firstMachine = 2
    private static let lastMachine = 254

    public var hubAddress: String { "\(prefix).\(hostAddress)" }

    /// The lowest address not in `taken` (full addresses such as "10.99.0.2").
    public func nextAddress(taken: Set<String>) throws -> String {
        for number in Self.firstMachine...Self.lastMachine where !taken.contains("\(prefix).\(number)") { return "\(prefix).\(number)" }
        throw WireGuardError.noFreeAddress
    }

    public struct Peer: Equatable, Sendable {
        public let name: String
        public let publicKey: String
        public let address: String
        public init(name: String, publicKey: String, address: String) {
            self.name = name
            self.publicKey = publicKey
            self.address = address
        }
    }

    /// The parent's config: its own key and port, and one [Peer] per machine that may only use its own single address.
    public func hubConfig(privateKey: String, peers: [Peer]) throws -> String {
        guard WireGuardKeyPair.publicKey(forPrivate: privateKey) != nil else { throw WireGuardError.badKey("the parent's private key") }
        var lines = ["[Interface]", "PrivateKey = \(privateKey)", "Address = \(hubAddress)/24", "ListenPort = \(Self.listenPort)", ""]
        for peer in peers {
            guard WireGuardKeyPair.isValidPublicKey(peer.publicKey) else { throw WireGuardError.badKey("the key of \(peer.name)") }
            lines += ["[Peer]", "# \(peer.name)", "PublicKey = \(peer.publicKey)", "AllowedIPs = \(peer.address)/32", ""]
        }
        return lines.joined(separator: "\n")
    }

    /// A machine's config. It reaches only the parent's private address, and keeps the connection alive through NATs.
    public func machineConfig(privateKey: String, address: String, hubPublicKey: String, hubEndpoint: String, hubPort: Int = listenPort) throws -> String {
        guard WireGuardKeyPair.publicKey(forPrivate: privateKey) != nil else { throw WireGuardError.badKey("the machine's private key") }
        guard WireGuardKeyPair.isValidPublicKey(hubPublicKey) else { throw WireGuardError.badKey("the parent's public key") }
        guard (1...65535).contains(hubPort) else { throw WireGuardError.badPort }
        return ["[Interface]", "PrivateKey = \(privateKey)", "Address = \(address)/32", "",
                "[Peer]", "PublicKey = \(hubPublicKey)", "Endpoint = \(hubEndpoint):\(hubPort)", "AllowedIPs = \(hubAddress)/32", "PersistentKeepalive = 25", ""].joined(separator: "\n")
    }
}
