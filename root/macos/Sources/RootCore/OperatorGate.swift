import Foundation

/// The rules that protect the operator listener, which has no sign-in: it is reachable only from this machine, only under its own name,
/// and a write must come from the panel itself. Pure, so each rule is tested on its own.
public enum OperatorGate {
    /// True for an address that stays on this machine.
    public static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "::1" || host == "127.0.0.1" || (host.hasPrefix("127.") && IPv4.isValid(host))
    }

    /// The Host header must be the host (and port) of the public URL. A page on another site that points its own name at this machine
    /// (DNS rebinding) sends its own name here, so it is refused.
    public static func hostMatches(header: String?, publicURL: String) -> Bool {
        guard let header, let wanted = URLComponents(string: publicURL), let host = wanted.host?.lowercased() else { return false }
        let expected = wanted.port.map { "\(host):\($0)" } ?? host
        return header.lowercased() == expected
    }
}
