import Foundation
import MSCore
import RootCore
import RootStore

/// Replaces the helper program of a machine the parent added over SSH, in one login and with one fixed script (see HelperUpdateScript). The parent logs in with its own key,
/// the one the operator authorised when adding the computer: the machine's restricted tunnel key has no shell. A machine that does not accept that key answers "login needed".
final class HelperUpdateService: @unchecked Sendable {
    struct Parts {
        let clock: Clock
        let ssh: RemoteSsh
        let machines: MachineStore
        let remoteMachines: RemoteMachineStore
        let commands: CommandStore
        let audit: AuditStore
        let updates: HelperUpdates
        let throttle: Throttle
    }

    static let updatesPerMinute = 2
    static let rateWindow: TimeInterval = 60
    /// Sending the program, stopping the old one, two waits of `HelperUpdateScript.settleSeconds` at the most, and some room.
    static let scriptSeconds: TimeInterval = 420
    static let auditAction = "helper.update"
    private static let unknownResult = "failed"

    private let parts: Parts
    private let lock = NSLock()
    private var updating: Set<String> = []

    init(parts: Parts) { self.parts = parts }

    func update(machine id: String, actor: String) async throws -> HelperUpdateResult {
        let machine: MachineSummary
        do { machine = try parts.machines.get(id: id, now: parts.clock.now) } catch MachineError.notFound { throw ApiFailure.notFound }
        do {
            guard parts.throttle.allow("helper-update:" + id, limit: Self.updatesPerMinute, seconds: Self.rateWindow) else { throw HelperUpdateFailure.tooManyTries }
            let result = try await perform(machine)
            record(actor, id, result: HelperUpdateScript.code(in: result.output))
            return result.answer
        } catch {
            record(actor, id, result: Self.auditName(of: error))
            throw error
        }
    }

    private func perform(_ machine: MachineSummary) async throws -> (answer: HelperUpdateResult, output: String) {
        guard let record = try parts.remoteMachines.get(machine.id) else { throw HelperUpdateFailure.loginNeeded }
        let offers = parts.updates.offers()
        let decision = parts.updates.status(of: machine, offers: offers)
        guard let system = HelperUpdateRules.system(os: machine.os, arch: machine.arch), let offer = offers[system] else { throw HelperUpdateFailure.noBuild(decision.reason ?? HelperUpdateRules.noBuildReason) }
        guard decision.available else { throw HelperUpdateFailure.upToDate }
        guard try !parts.commands.hasUnfinishedOrder(machine: machine.id) else { throw HelperUpdateFailure.busy }
        try begin(machine.id)
        defer { end(machine.id) }
        let output = try await replace(record, with: offer)
        return (HelperUpdateScript.outcome(output: output), output)
    }

    private func replace(_ record: RemoteMachine, with offer: HelperUpdates.Offer) async throws -> String {
        guard let program = FileManager.default.contents(atPath: offer.path) else { throw HelperUpdateFailure.noBuild(HelperUpdateRules.noBuildReason) }
        let script = try HelperUpdateScript.make(box: record.box, agentPort: record.agentPort, expectedBuild: offer.build)
        let target = try RemoteTarget(host: record.host, port: record.sshPort, user: record.sshUser)
        let credentials = try await login(record, target)
        let result = try await parts.ssh.run(command: "sh -c " + Shell.quote(script), input: program, on: target, with: credentials, timeout: Self.scriptSeconds)
        guard result.status == 0 else { throw Self.loginFailure(result) }
        return result.output
    }

    /// The same checks as the other steps over SSH: an address that is allowed, a few tries a minute, and the host key must be the one pinned when the machine was added.
    private func login(_ record: RemoteMachine, _ target: RemoteTarget) async throws -> SshCredentials {
        _ = try parts.ssh.allowedAddress(target)
        try parts.ssh.allowTry(target)
        let key = try await parts.ssh.scanKey(target)
        guard key.fingerprint == record.fingerprint else { throw RemoteFailure.hostKeyChanged }
        try parts.ssh.trust(key.line)
        return try await parts.ssh.credentials(.parentKey)
    }

    /// A login the computer refused means the parent's key is not there: the operator has to add the computer again. Anything else is told as it is.
    private static func loginFailure(_ result: SshResult) -> Error {
        let failure = RemoteFailure.fromSsh(result.errors, status: result.status, auth: .key(path: ""))
        switch failure {
        case .loginRefused, .keyNotAccepted, .passwordNotAccepted: return HelperUpdateFailure.loginNeeded
        default: return failure
        }
    }

    private func begin(_ id: String) throws {
        try lock.withLock {
            guard updating.insert(id).inserted else { throw HelperUpdateFailure.busy }
        }
    }

    private func end(_ id: String) { lock.withLock { _ = updating.remove(id) } }

    private func record(_ actor: String, _ id: String, result: String) {
        try? parts.audit.record(actor: actor, action: Self.auditAction, target: id, detail: ["result": result], at: parts.clock.now)
    }

    private static func auditName(of error: Error) -> String {
        if let failure = error as? HelperUpdateFailure { return failure.auditName }
        if let failure = error as? RemoteFailure { return failure.auditName }
        return unknownResult
    }
}
