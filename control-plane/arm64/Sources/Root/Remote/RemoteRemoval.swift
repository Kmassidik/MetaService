import Foundation
import MSCore
import RootCore
import RootStore

/// Removing a machine that was installed over SSH. Either log in once more and take everything the install added away (the box, the key line), then forget the machine here;
/// or only forget it here, when the computer is gone. The VM tool, if the computer already had it, is never touched.
extension RemoteInstallService {
    private static let removalSeconds: TimeInterval = 60

    func remove(machine: String, request: RemoteRemoveRequest, actor: String) async throws {
        guard let record = try parts.remoteMachines.get(machine) else { throw RemoteFailure.notRemote }
        parts.tunnels.forget(machine)
        if let login = request.login { try await takeAway(record, login) }
        try forget(record)
        try? parts.audit.record(actor: actor, action: request.forgetOnly ? "remote.forget" : "remote.remove", target: machine, detail: ["host": record.host, "box": record.box], at: parts.clock.now)
    }

    private func takeAway(_ record: RemoteMachine, _ login: RemoteLoginRequest.Login) async throws {
        let target = try RemoteTarget(host: record.host, port: record.sshPort, user: record.sshUser)
        _ = try parts.ssh.allowedAddress(target)
        try parts.ssh.allowTry(target)
        let key = try await parts.ssh.scanKey(target)
        guard key.fingerprint == record.fingerprint else { throw RemoteFailure.hostKeyChanged }
        let credentials = try await parts.ssh.credentials(login)
        let removedKey = zip(record.keyFile, record.keyMarker).map { PlanScripts.RemovedKey(file: $0, marker: $1, fileCreated: record.keyFileCreated, directoryCreated: record.sshDirCreated) }
        let script = PlanScripts.removeScript(box: record.box, key: removedKey)
        let result = try await parts.ssh.run(script, on: target, with: credentials, timeout: Self.removalSeconds)
        guard result.status == 0 else { throw removalFailure(result) }
    }

    private func removalFailure(_ result: SshResult) -> Error {
        if let line = result.output.split(separator: "\n").first(where: { $0.hasPrefix("ms-error:") }) { return InstallFailure(String(line.dropFirst("ms-error:".count)).trimmingCharacters(in: .whitespaces)) }
        return RemoteFailure.fromSsh(result.errors, status: result.status)
    }

    private func forget(_ record: RemoteMachine) throws {
        try? parts.machines.remove(id: record.machine)
        try parts.chatAccess.remove(target: record.machine)
        try parts.settings.remove(machine: record.machine)
        try parts.ssh.pins.forget(spec: HostKeys.spec(host: record.host, port: record.sshPort))
        try parts.ssh.machineKeyRemove(record.machine)
        try parts.remoteMachines.remove(record.machine)
    }
}

private func zip<A, B>(_ first: A?, _ second: B?) -> (A, B)? {
    guard let first, let second else { return nil }
    return (first, second)
}
