import Foundation
import MSCore
import RootCore
import RootStore

/// "Install it for me": installs one missing part on another computer through the SSH login the parent already uses, with the person's sudo password, then checks the computer
/// again. The password is read from the request, written to the other computer's `sudo -S` once, and wiped when this ends. It is never logged, audited, stored or returned.
/// The login is either a typed address or a machine that is already added; either way this adds no machine and records nothing but the audit line.
final class RemoteFixService: @unchecked Sendable {
    private let ssh: RemoteSsh
    private let config: RootConfig
    private let audit: AuditStore
    private let clock: Clock
    private let records: RemoteRecords

    private static let loginSeconds: TimeInterval = 40
    private static let installSeconds: TimeInterval = 900
    private static let sshFailureStatus: Int32 = 255

    init(ssh: RemoteSsh, config: RootConfig, audit: AuditStore, clock: Clock, remoteMachines: RemoteMachineStore) {
        self.ssh = ssh
        self.config = config
        self.audit = audit
        self.clock = clock
        records = RemoteRecords(store: remoteMachines)
    }

    func fix(_ request: RemoteFixRequest, actor: String) async throws -> VerifyResult {
        defer { request.sudoPassword.wipe() }
        do {
            let login = try records.resolved(request.target, login: request.login)
            let result = try await install(login, part: request.part, sudoPassword: request.sudoPassword)
            record(actor, request.target, part: request.part, outcome: "ok")
            return result
        } catch let failure as RemoteFailure {
            record(actor, request.target, part: request.part, outcome: failure.auditName)
            throw failure
        }
    }

    private func install(_ login: ResolvedLogin, part: MissingPart, sudoPassword: SudoPassword) async throws -> VerifyResult {
        let target = login.target
        _ = try ssh.allowedAddress(target)
        try ssh.allowTry(target)
        let key = try await ssh.scanKey(target)
        guard key.fingerprint == login.fingerprint else { throw RemoteFailure.fingerprintMismatch }
        try ssh.trust(key.line)
        let credentials = try await ssh.credentials(login.login)
        let before = try await RemoteService.readFacts(ssh, target, credentials)
        if alreadyThere(part, before) { return result(target, key.fingerprint, before) }
        guard InstallOffers.offer(for: part, facts: before) != nil else { throw RemoteFailure.fixUnavailable }
        try await runInstall(part: part, sudoPassword: sudoPassword, user: before.user, box: before.box, target: target, credentials: credentials)
        return result(target, key.fingerprint, try await RemoteService.readFacts(ssh, target, credentials))
    }

    private func alreadyThere(_ part: MissingPart, _ facts: RemoteFacts) -> Bool {
        switch part {
        case .vmTool: return facts.tools.contains("incus")
        case .python: return facts.tools.contains("python3")
        case .gpuToolkit: return facts.hasGpuToolkit
        case .vmPackages: return facts.kvm == true && facts.qemu == true
        case .autostart: return facts.autostart == true
        }
    }

    private func runInstall(part: MissingPart, sudoPassword: SudoPassword, user: String, box: String, target: RemoteTarget, credentials: SshCredentials) async throws {
        let script = InstallMissingScripts.script(for: part, user: user, box: box)
        let command = InstallMissingScripts.sudoCommand(script: script, withPassword: !sudoPassword.isEmpty)
        let sent = try await ssh.run(command: command, input: sudoPassword.standardInput(), on: target, with: credentials, timeout: Self.installSeconds)
        if sent.status == Self.sshFailureStatus { throw RemoteFailure.fromSsh(sudoPassword.redacted(sent.errors), status: sent.status, auth: credentials.auth) }
        guard let failure = MissingOutcome.read(status: sent.status, output: sent.output, errors: sent.errors, password: sudoPassword) else { return }
        throw RemoteFailure.missing(failure)
    }

    private func result(_ target: RemoteTarget, _ fingerprint: String, _ facts: RemoteFacts) -> VerifyResult {
        RemoteService.result(target.host, fingerprint, facts, parentURL: ssh.parentURL, builds: Set(AgentBuilds.available(config: config).keys))
    }

    private func record(_ actor: String, _ target: RemoteLoginTarget, part: MissingPart, outcome: String) {
        let named: String
        switch target {
        case .typed(let typed, _): named = "\(typed.user)@\(typed.host):\(typed.port)"
        case .stored(let machine): named = machine
        }
        try? audit.record(actor: actor, action: "remote.fix", target: named, detail: ["part": part.rawValue, "result": outcome], at: clock.now)
    }
}
