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
    public static func login(target: RemoteTarget, auth: SshAuth, knownHosts: String, command: [String]) -> [String] {
        common(target: target, auth: auth, knownHosts: knownHosts) + ["--", "\(target.user)@\(target.host)"] + command
    }

    /// `ssh -N -L local:127.0.0.1:remote user@host`: keeps a tunnel from a local port to the Agent's loopback port on the other computer.
    public static func tunnel(target: RemoteTarget, keyPath: String, knownHosts: String, localPort: Int, remotePort: Int) -> [String] {
        common(target: target, auth: .key(path: keyPath), knownHosts: knownHosts)
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
