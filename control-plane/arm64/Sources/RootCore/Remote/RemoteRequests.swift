import Foundation
import MSCore

/// Step one of Connect: ask a computer for its SSH host key, so the operator can confirm its fingerprint before any login.
public struct ProbeRequest: Equatable {
    public let target: RemoteTarget

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["host", "port"])
        target = try Self.target(object, user: "probe")
    }

    static func target(_ object: StrictObject, user: String) throws -> RemoteTarget {
        do {
            return try RemoteTarget(host: try object.string("host", maxLength: 253, minLength: 1), port: object.has("port") ? try object.int("port", range: 1...65535) : nil, user: user)
        } catch RemoteTargetError.badHost {
            throw InputError("host must be an address or a host name")
        } catch RemoteTargetError.badUser {
            throw InputError("user is not a valid account name")
        } catch RemoteTargetError.badPort {
            throw InputError("port must be 1 to 65535")
        }
    }
}

/// The part of a login request that Verify and Add share: where, as whom, how, and the host key the operator confirmed.
public struct RemoteLoginRequest: Equatable {
    public enum Login: Equatable {
        case password(String)
        case parentKey
    }

    public let target: RemoteTarget
    public let login: Login
    public let fingerprint: String

    public static let longestPassword = 256
    static let fields: Set<String> = ["host", "port", "user", "password", "use_key", "fingerprint"]

    init(_ object: StrictObject) throws {
        let typed = try Self.typed(object)
        target = typed.target
        fingerprint = typed.fingerprint
        login = try Self.login(object)
    }

    /// Where, as whom, and the host key the operator confirmed.
    static func typed(_ object: StrictObject) throws -> (target: RemoteTarget, fingerprint: String) {
        let user = try object.string("user", maxLength: 32, minLength: 1)
        let fingerprint = try object.string("fingerprint", maxLength: 80)
        guard HostKeys.isFingerprint(fingerprint) else { throw InputError("fingerprint is not an SHA256 host key fingerprint") }
        return (try ProbeRequest.target(object, user: user), fingerprint)
    }

    /// Just how: a password used once, or the parent's own key. Shared by every request that logs in, including a re-check that names a machine instead of an address.
    static func login(_ object: StrictObject) throws -> Login {
        let useKey = object.has("use_key") ? try object.bool("use_key") : false
        let password = try object.optionalString("password", maxLength: Self.longestPassword) ?? ""
        switch (useKey, password.isEmpty) {
        case (true, true): return .parentKey
        case (false, false): return .password(password)
        case (true, false): throw InputError("give a password or use the key, not both")
        case (false, true): throw InputError("give a password, or use the parent's key")
        }
    }
}

/// Step two of Connect: log in and read what the computer is. Either a password (used once, never kept) or the parent's own key.
/// The computer is either the address typed in now, or a machine that is already added (see RemoteLoginTarget).
public struct VerifyRequest: Equatable {
    public typealias Login = RemoteLoginRequest.Login

    public let target: RemoteLoginTarget
    public let login: Login

    public static let longestPassword = RemoteLoginRequest.longestPassword

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: RemoteLoginRequest.fields.union([RemoteLoginTarget.machineField]))
        target = try RemoteLoginTarget.parse(object)
        login = try RemoteLoginRequest.login(object)
    }
}

/// What the operator may change about the install, besides the machine's own settings. Every field is optional; what is left out is the safe default.
public struct InstallChoices: Equatable {
    public let name: String
    public let box: String?
    public let sshDirectory: String?
    public let agentPort: Int?
    public let installKey: Bool
    public let chat: Bool
    public let settings: MachineSettings

    static let fields: Set<String> = Set(["name", "box", "ssh_dir", "agent_port", "install_key", "chat"]).union(MachineSettings.fields)

    init(_ object: StrictObject) throws {
        name = try object.id("name")
        box = try Self.plainPath(object, "box")
        sshDirectory = try Self.plainPath(object, "ssh_dir")
        agentPort = object.has("agent_port") ? try object.int("agent_port", range: 1024...65000) : nil
        installKey = object.has("install_key") ? try object.bool("install_key") : true
        chat = object.has("chat") ? try object.bool("chat") : false
        settings = try MachineSettings(object)
    }

    private static func plainPath(_ object: StrictObject, _ key: String) throws -> String? {
        guard let path = try object.optionalString(key, maxLength: 200) else { return nil }
        guard RemoteInstallOptions.isPlainPath(path) else { throw InputError("\(key) must be a plain absolute path (letters, digits and . _ @ + / - only)") }
        return path
    }

    /// The options for a computer whose home folder and engine are known, with these choices on top of the defaults. Checked, so a bad path or port stops here.
    public func options(home: String, engine: String, rootURL: String) throws -> RemoteInstallOptions {
        var value = RemoteInstallOptions.defaults(name: name, home: home, engine: engine, rootURL: rootURL, settings: settings)
        value.box = box ?? value.box
        value.sshDirectory = sshDirectory ?? value.sshDirectory
        value.agentPort = agentPort ?? value.agentPort
        value.installKey = installKey
        value.chat = chat
        return try value.validated()
    }
}

/// "Add machine" for another computer: the login of Verify plus the choices. This is the one request that changes anything on that computer.
public struct RemoteAddRequest: Equatable {
    public let login: RemoteLoginRequest
    public let choices: InstallChoices

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: RemoteLoginRequest.fields.union(InstallChoices.fields))
        login = try RemoteLoginRequest(object)
        choices = try InstallChoices(object)
    }
}

/// "What will change", asked before Add: the plan for a computer, with no login and no change anywhere. The home folder and the system come from Verify.
public struct PlanRequest: Equatable {
    public let host: String
    public let home: String
    public let isMac: Bool
    public let choices: InstallChoices

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: InstallChoices.fields.union(["host", "home", "os"]))
        host = try object.string("host", maxLength: 253, minLength: 1)
        home = try object.string("home", maxLength: 200)
        guard RemoteInstallOptions.isPlainPath(home) else { throw InputError("home is not a plain absolute path") }
        isMac = try object.choice("os", among: ["Darwin", "Linux"]) == "Darwin"
        choices = try InstallChoices(object)
    }
}

/// Removing a machine that was installed over SSH: log in once more to take MetaService off that computer, or only forget it here (when the computer is gone).
public struct RemoteRemoveRequest: Equatable {
    public let forgetOnly: Bool
    public let login: RemoteLoginRequest.Login?

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["password", "use_key", "forget_only"])
        forgetOnly = object.has("forget_only") ? try object.bool("forget_only") : false
        let useKey = object.has("use_key") ? try object.bool("use_key") : false
        let password = try object.optionalString("password", maxLength: RemoteLoginRequest.longestPassword) ?? ""
        switch (forgetOnly, useKey, password.isEmpty) {
        case (true, false, true): login = nil
        case (true, _, _): throw InputError("forgetting only needs no login")
        case (false, true, true): login = .parentKey
        case (false, false, false): login = .password(password)
        case (false, true, false): throw InputError("give a password or use the key, not both")
        case (false, false, true): throw InputError("give a password, or use the parent's key, or choose to forget only")
        }
    }
}
