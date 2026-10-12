import Foundation

/// How the parent reaches the Agent of one machine. The dashboard and the Agent client do not care which one is used.
public enum TransportKind: String, Equatable, Sendable {
    case sshTunnel = "ssh_tunnel"
    case wireGuard = "wireguard"
}

public enum TransportState: Equatable, Sendable {
    case connected(since: Date)
    case offline(reason: String)
}

/// The three things every transport can do. `open` makes the parent's side of the channel and answers where to call the Agent; `state` says whether it works now; `close` takes it down.
public protocol MachineTransport: Sendable {
    var kind: TransportKind { get }
    func open(machine: String) async throws -> (host: String, port: Int)
    func state(machine: String) async -> TransportState
    func close(machine: String) async
}
