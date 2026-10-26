import Foundation
import RootCore
import RootStore

/// Where a login goes, taken from the request: a typed address, or the record of a machine that is already added.
/// Read-only: a check resolves the record before it opens any connection, and nothing is ever written back.
struct RemoteRecords {
    let store: RemoteMachineStore

    func resolved(_ target: RemoteLoginTarget, login: RemoteLoginRequest.Login) throws -> ResolvedLogin {
        let stored = try target.storedMachine.flatMap { try store.stored($0) }
        guard let resolved = target.resolved(login: login, stored: stored) else { throw RemoteFailure.notRemote }
        return resolved
    }
}
