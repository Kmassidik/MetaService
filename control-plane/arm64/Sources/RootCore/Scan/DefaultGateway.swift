import Foundation

/// Reads the gateway address out of `route -n get default` (macOS): a line like `    gateway: 192.168.0.1`.
public enum DefaultGateway {
    private static let line = try! Regex(#"gateway:\s*(\d{1,3}(?:\.\d{1,3}){3})"#)

    public static func parse(_ output: String) -> String? {
        guard let match = output.firstMatch(of: line), let ip = match.output[1].substring.map(String.init), Subnet.address(ip) != nil else { return nil }
        return ip
    }
}
