import Foundation

/// Machines that joined through Share a PC reach the parent from the join-share network (`10.77.0.0/24`, see join-share/CONTRACT.md). Pure.
public enum McpShared {
    public static let networkPrefix = "10.77.0."

    public static func isShared(ip: String?) -> Bool {
        guard let ip else { return false }
        return ip.hasPrefix(networkPrefix)
    }
}
