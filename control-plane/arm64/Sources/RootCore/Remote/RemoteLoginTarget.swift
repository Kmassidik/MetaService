import Foundation

/// Which computer a login is for: one whose address and confirmed host key the request carries, or one that is already added, whose own record has both.
/// A re-check uses the second, so it can only ever look at the machine that is already there: never a second machine, and never another address.
public enum RemoteLoginTarget: Equatable {
    case typed(RemoteTarget, fingerprint: String)
    case stored(machine: String)

    /// The field that names a machine that is already added.
    public static let machineField = "machine"

    /// The address and host key, or the name of the machine. A request gives one or the other, never both: a re-check must not be able to look somewhere else.
    static func parse(_ object: StrictObject) throws -> RemoteLoginTarget {
        guard object.has(machineField) else {
            let typed = try RemoteLoginRequest.typed(object)
            return .typed(typed.target, fingerprint: typed.fingerprint)
        }
        guard !object.keys.isDisjoint(with: ["host", "port", "user", "fingerprint"]) else {
            return .stored(machine: try object.id(machineField))
        }
        throw InputError("give the machine, or an address and a host key, not both")
    }

    /// The machine that is already added, or nil when the request carries an address.
    public var storedMachine: String? {
        guard case .stored(let machine) = self else { return nil }
        return machine
    }
}

/// What a re-check takes from the record of a machine added over SSH: where it is, as whom, and the host key trusted when it was added.
public struct StoredMachine: Equatable {
    public let host: String
    public let port: Int
    public let user: String
    public let fingerprint: String

    public init(host: String, port: Int, user: String, fingerprint: String) {
        self.host = host
        self.port = port
        self.user = user
        self.fingerprint = fingerprint
    }
}

/// Where a login goes, once the address is known: exactly what the SSH code needs.
public struct ResolvedLogin: Equatable {
    public let target: RemoteTarget
    public let fingerprint: String
    public let login: RemoteLoginRequest.Login
}

extension RemoteLoginTarget {
    /// The address, host key and login of a request. Nil when it names a machine that has no record: it was not added over SSH (or is gone since),
    /// and a check must never guess an address. The caller turns that into its refusal.
    public func resolved(login: RemoteLoginRequest.Login, stored: StoredMachine?) -> ResolvedLogin? {
        switch self {
        case .typed(let target, let fingerprint):
            return ResolvedLogin(target: target, fingerprint: fingerprint, login: login)
        case .stored:
            guard let stored, let target = try? RemoteTarget(host: stored.host, port: stored.port, user: stored.user) else { return nil }
            return ResolvedLogin(target: target, fingerprint: stored.fingerprint, login: login)
        }
    }
}
