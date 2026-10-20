import Foundation

public enum SshAuth: Equatable, Sendable {
    /// The password comes from an askpass helper, never from the command line.
    case password
    /// The parent's own key file.
    case key(path: String)
}

/// The command lines of the ssh program, built in one place. Never through a shell, never with a password in them.
public enum SshArguments {
    public static let connectSeconds = 10

    /// `ssh ... user@host command...`: one login that runs one command (the command can be `sh -s`, with a script on its input).
    /// With `reversePort`, the other computer's `127.0.0.1:<reversePort>` leads back to the parent's own listener on the same port, for as long as this login lasts.
    public static func login(target: RemoteTarget, auth: SshAuth, knownHosts: String, command: [String], reversePort: Int? = nil) -> [String] {
        common(target: target, auth: auth, knownHosts: knownHosts) + reverse(reversePort) + ["--", "\(target.user)@\(target.host)"] + command
    }

    private static func reverse(_ port: Int?) -> [String] {
        guard let port else { return [] }
        return ["-o", "ExitOnForwardFailure=yes", "-R", "127.0.0.1:\(port):127.0.0.1:\(port)"]
    }

    /// Asks which logins a computer accepts, without trying any: the "none" login is always refused, and ssh then prints the list in its refusal. No secret is sent and
    /// the host key is not trusted by this (that stays the operator's decision), so the key check is off for this one call only.
    public static func methodsProbe(target: RemoteTarget) -> [String] {
        ["-F", "/dev/null", "-p", String(target.port), "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "GlobalKnownHostsFile=/dev/null",
         "-o", "ConnectTimeout=\(connectSeconds)", "-o", "BatchMode=yes", "-o", "PreferredAuthentications=none", "-o", "PubkeyAuthentication=no", "-o", "LogLevel=ERROR",
         "--", "\(probeUser)@\(target.host)", "true"]
    }

    /// A user name that does not exist anywhere, so the probe never looks like a try at a real account.
    static let probeUser = "metaservice-probe"

    /// `ssh -N -L local:127.0.0.1:remote user@host`: keeps a tunnel from a local port to the Agent's loopback port on the other computer (and, with `reversePort`, the way back to the parent).
    public static func tunnel(target: RemoteTarget, keyPath: String, knownHosts: String, localPort: Int, remotePort: Int, reversePort: Int? = nil) -> [String] {
        common(target: target, auth: .key(path: keyPath), knownHosts: knownHosts) + reverse(reversePort)
            + ["-N", "-o", "ExitOnForwardFailure=yes", "-L", "127.0.0.1:\(localPort):127.0.0.1:\(remotePort)", "--", "\(target.user)@\(target.host)"]
    }

    static func common(target: RemoteTarget, auth: SshAuth, knownHosts: String) -> [String] {
        // -F /dev/null: the operator's own ssh configuration (proxies, includes, host rules) must never change what the parent does.
        var arguments = ["-F", "/dev/null", "-p", String(target.port),
                         "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=\(knownHosts)", "-o", "GlobalKnownHostsFile=/dev/null",
                         "-o", "ConnectTimeout=\(connectSeconds)", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
                         "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "ControlMaster=no", "-o", "LogLevel=ERROR"]
        switch auth {
        case .password:
            arguments += ["-o", "BatchMode=no", "-o", "PubkeyAuthentication=no", "-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "NumberOfPasswordPrompts=1"]
        case .key(let path):
            arguments += ["-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "PasswordAuthentication=no", "-i", path]
        }
        return arguments
    }
}
