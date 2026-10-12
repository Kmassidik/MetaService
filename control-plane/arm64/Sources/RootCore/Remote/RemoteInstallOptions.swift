import Foundation
import MSCore

public enum Isolation: String, Equatable, Sendable {
    /// A folder of the SSH user: nothing else on the computer is touched, no admin rights needed.
    case folder
    /// A user of its own and a service: needs admin rights (sudo).
    case dedicatedUser = "dedicated_user"
}

public enum RemoteInstallError: Error, Equatable {
    case badPath(String)
    case badPort(String)
    case notAvailable(String)
}

/// Everything the install needs to know, checked before any plan is made. A path is absolute and made only of plain characters, so it is safe in a script.
public struct RemoteInstallOptions: Equatable, Sendable {
    public var name: String
    public var level: Isolation
    public var box: String
    public var sshDirectory: String
    public var agentPort: Int
    public var engine: String
    public var rootURL: String
    public var installKey: Bool
    public var installVmTool: Bool
    public var settings: MachineSettings
    public var chat: Bool

    public static let defaultAgentPort = 9101
    public static let chatPortOffset = 99
    public static let boxFolderName = "metaservice-box"
    private static let pathPattern = try! NSRegularExpression(pattern: "^/[A-Za-z0-9._@+/-]{1,200}$")

    public var chatPort: Int { agentPort + Self.chatPortOffset }

    /// The defaults for a computer whose home folder is `home`: the box and the key line go where the install of this level goes.
    public static func defaults(name: String, home: String, engine: String, rootURL: String, settings: MachineSettings = MachineSettings()) -> RemoteInstallOptions {
        RemoteInstallOptions(name: name, level: .folder, box: home + "/" + boxFolderName, sshDirectory: home + "/.ssh", agentPort: defaultAgentPort, engine: engine, rootURL: rootURL,
                             installKey: true, installVmTool: false, settings: settings, chat: false)
    }

    /// Refuses what could be unsafe or unsupported. The name is a machine id (the same rule as a local machine).
    public func validated() throws -> RemoteInstallOptions {
        guard Ids.isValid(name) else { throw RemoteInstallError.badPath("the machine name") }
        for (label, path) in [("the box folder", box), ("the ssh folder", sshDirectory)] where !Self.isPlainPath(path) { throw RemoteInstallError.badPath(label) }
        guard (1024...65000).contains(agentPort) else { throw RemoteInstallError.badPort("the Agent port must be 1024 to 65000") }
        guard ["apple", "incus", "simulated"].contains(engine) else { throw RemoteInstallError.notAvailable("the engine is apple, incus or simulated") }
        guard level == .folder else { throw RemoteInstallError.notAvailable("a user of its own is not available yet") }
        guard !installVmTool else { throw RemoteInstallError.notAvailable("installing the VM tool on another computer is not available yet") }
        return self
    }

    public static func isPlainPath(_ path: String) -> Bool {
        let whole = NSRange(path.startIndex..., in: path)
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return pathPattern.firstMatch(in: path, range: whole) != nil && !path.contains("//") && !parts.contains("..") && !parts.contains(".") && path != "/"
    }
}
