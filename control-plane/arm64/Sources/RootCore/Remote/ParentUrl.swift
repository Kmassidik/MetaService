import Foundation

/// Where another computer reaches the parent's agent listener. A computer on this one (loopback, used by tests and demos) reaches it on loopback. A real one needs the
/// parent to listen on a network address: the one set in ROOT_AGENT_BIND, or, when that is "0.0.0.0", this computer's address on the target's network.
public enum ParentUrl {
    public static func make(bind: String, port: Int, target: String, localAddresses: [String]) -> String? {
        if IPv4.isLoopback(target) { return "http://127.0.0.1:\(port)" }
        guard !IPv4.isLoopback(bind), IPv4.isValid(bind) else { return nil }
        guard bind == "0.0.0.0" else { return "http://\(bind):\(port)" }
        guard let address = localAddresses.first(where: { sameNetwork($0, target) }) else { return nil }
        return "http://\(address):\(port)"
    }

    /// The same /24, the usual size of an office or home network.
    static func sameNetwork(_ first: String, _ second: String) -> Bool {
        guard let left = Subnet.address(first), let right = Subnet.address(second) else { return false }
        return left & 0xFFFFFF00 == right & 0xFFFFFF00
    }
}
