import Foundation

/// Which machines are reached through an SSH tunnel, and on which local port each tunnel is open right now. A machine that is meant to have a tunnel is NEVER called
/// directly: while its tunnel is down the call fails, so the Agent that listens only on that computer's loopback is never expected to answer on its network address.
final class TunnelPorts: @unchecked Sendable {
    private enum Route { case expected, open(Int) }
    private let lock = NSLock()
    private var routes: [String: Route] = [:]

    func expect(_ machine: String) { lock.withLock { if routes[machine] == nil { routes[machine] = .expected } } }
    func open(_ machine: String, port: Int) { lock.withLock { routes[machine] = .open(port) } }
    func close(_ machine: String) { lock.withLock { routes[machine] = .expected } }
    func forget(_ machine: String) { lock.withLock { _ = routes.removeValue(forKey: machine) } }

    /// nil: this machine has no tunnel, call it directly. .some(nil): it has one, but it is down. .some(port): call this local port.
    func route(for machine: String) -> Int?? {
        lock.withLock {
            switch routes[machine] {
            case .none: return .none
            case .expected: return .some(nil)
            case .open(let port): return .some(port)
            }
        }
    }
}
