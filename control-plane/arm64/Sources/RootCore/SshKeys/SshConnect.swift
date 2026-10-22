import Foundation

/// How a person reaches a VM from their laptop: the jump (the machine, as `user@host[:port]`) and the one command built from it.
/// Where it lives: `RootCore/SshKeys`. Pure and strict: every part is checked again here, so no free text can ever end up in the command.
public enum SshConnect {
    public static let maxJumpCharacters = 120
    static let sshPort = 22
    static let portRange = 1...65535
    static let jumpPattern = #/^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+(?::[0-9]{1,5})?$/#
    static let hostNamePattern = #/^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$/#
    static let ipv4Pattern = #/^[0-9]{1,3}(\.[0-9]{1,3}){3}$/#
    static let ipv6Pattern = #/^[0-9A-Fa-f:]{2,45}$/#
    static let userPattern = #/^[A-Za-z0-9._-]+$/#
    static let maxAddressCharacters = 253
    static let minIpv6Colons = 2

    /// True when the text is exactly `user@host` or `user@host:port` with a port that fits.
    public static func isValidJump(_ text: String) -> Bool {
        guard text.count <= maxJumpCharacters, text.wholeMatch(of: jumpPattern) != nil else { return false }
        guard let colon = text.lastIndex(of: ":") else { return true }
        return Int(text[text.index(after: colon)...]).map(portRange.contains) ?? false
    }

    /// The jump for a machine added over SSH: `user@host`, plus `:port` when the port is not the usual one. Nil when any part is not plain.
    public static func defaultJump(user: String, host: String, port: Int) -> String? {
        guard user.wholeMatch(of: userPattern) != nil, host.wholeMatch(of: hostNamePattern) != nil, portRange.contains(port) else { return nil }
        let jump = port == sshPort ? "\(user)@\(host)" : "\(user)@\(host):\(port)"
        return isValidJump(jump) ? jump : nil
    }

    /// An IPv4 or IPv6 address, or a host name. Nothing with spaces, quotes or shell characters passes.
    public static func isValidVmAddress(_ text: String) -> Bool {
        guard text.count <= maxAddressCharacters else { return false }
        if text.wholeMatch(of: ipv4Pattern) != nil || text.wholeMatch(of: hostNamePattern) != nil { return true }
        return text.wholeMatch(of: ipv6Pattern) != nil && text.filter { $0 == ":" }.count >= minIpv6Colons && text.contains { $0 != ":" }
    }

    /// How the machine is reached: the setting if there is a valid one, otherwise the address the machine was added with (then `isDefault`), otherwise nothing.
    public static func resolveJump(setting: String?, office: (user: String, host: String, port: Int)?) -> (jump: String?, isDefault: Bool) {
        if let setting, isValidJump(setting) { return (setting, false) }
        guard let office, let jump = defaultJump(user: office.user, host: office.host, port: office.port) else { return (nil, false) }
        return (jump, true)
    }

    /// `ssh -J <jump> root@<address>`, or nil when either part is missing or not plain.
    public static func command(jump: String?, vmAddress: String?) -> String? {
        guard let jump, let vmAddress, isValidJump(jump), isValidVmAddress(vmAddress) else { return nil }
        return "ssh -J \(jump) root@\(vmAddress)"
    }
}
