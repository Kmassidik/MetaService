import Foundation
import MSCore
import RootCore
import RootStore

struct ProbeResult: Encodable {
    let host: String
    let address: String
    let keyType: String
    let fingerprint: String
    /// True when this computer's key is already trusted (it was confirmed before).
    let trusted: Bool
    /// The logins that computer accepts, as ssh names them ("publickey", "password"...). Nil when it did not say; the page then offers both ways.
    let loginMethods: [String]?
}

struct VerifyResult: Encodable {
    let host: String
    let fingerprint: String
    let facts: FactsView
    let requirements: [Requirement]
    let canAdd: Bool
    let isolation: [String]
    let system: String

    struct FactsView: Encodable {
        let os: String, arch: String, version: String, chip: String, user: String, home: String, computerName: String
        let cpuCores: Int?, ramMb: Int?, diskFreeGb: Int?
    }
}

/// Connect: look at another computer over SSH without changing it. Step one shows its host key; step two logs in (a password used once and never kept,
/// or the parent's own key) and reads what the computer is. Only computers on this network are allowed, and a key we trusted is never replaced.
/// The same step two checks a machine that is already added ("Check again"): it reads that machine's own record for the address and host key, and writes nothing.
final class RemoteService: @unchecked Sendable {
    private let ssh: RemoteSsh
    private let config: RootConfig
    private let audit: AuditStore
    private let clock: Clock
    private let records: RemoteRecords

    private static let loginSeconds: TimeInterval = 40

    init(ssh: RemoteSsh, config: RootConfig, audit: AuditStore, clock: Clock, remoteMachines: RemoteMachineStore) {
        self.ssh = ssh
        self.config = config
        self.audit = audit
        self.clock = clock
        records = RemoteRecords(store: remoteMachines)
    }

    // MARK: step one

    func probe(_ target: RemoteTarget, actor: String) async throws -> ProbeResult {
        let address = try ssh.allowedAddress(target)
        let key = try await ssh.scanKey(target)
        let status = ssh.pins.status(of: key.line)
        guard status != .changed else { throw RemoteFailure.hostKeyChanged }
        record(actor, "remote.probe", target, ["result": "ok", "address": address])
        return ProbeResult(host: target.host, address: address, keyType: key.line.split(separator: " ")[1].description, fingerprint: key.fingerprint, trusted: status == .same, loginMethods: await ssh.loginMethods(target))
    }

    // MARK: step two

    /// A check of a typed address, or (`machine`) of one that is already added: the same read, and nothing is written to the database.
    func verify(_ request: VerifyRequest, actor: String) async throws -> VerifyResult {
        do {
            let login = try records.resolved(request.target, login: request.login)
            let result = try await verifyChecked(login)
            record(actor, "remote.verify", login.target, ["result": "ok", "system": result.system])
            return result
        } catch let failure as RemoteFailure {
            recordRefusal(actor, request.target, failure)
            throw failure
        }
    }

    private func verifyChecked(_ request: ResolvedLogin) async throws -> VerifyResult {
        let target = request.target
        _ = try ssh.allowedAddress(target)
        try ssh.allowTry(target)
        let key = try await ssh.scanKey(target)
        guard key.fingerprint == request.fingerprint else { throw RemoteFailure.fingerprintMismatch }
        try ssh.trust(key.line)
        let credentials = try await ssh.credentials(request.login)
        let facts = try await Self.readFacts(ssh, target, credentials)
        return Self.result(target.host, key.fingerprint, facts, parentURL: ssh.parentURL, builds: Set(AgentBuilds.available(config: config).keys))
    }

    /// The same read the installer does again just before it changes anything.
    static func readFacts(_ ssh: RemoteSsh, _ target: RemoteTarget, _ credentials: SshCredentials) async throws -> RemoteFacts {
        let result = try await ssh.run(RemoteProbe.script, on: target, with: credentials, timeout: loginSeconds)
        if result.status != 0, SshErrors.looksLikeWindows(result.errors) { return RemoteProbe.windows(user: target.user) }
        guard result.status == 0 else {
            RemoteLog.say("ssh to \(target.user)@\(target.host):\(target.port) ended with status \(result.status): \(result.errors)")
            throw RemoteFailure.fromSsh(result.errors, status: result.status, auth: credentials.auth)
        }
        guard let facts = RemoteProbe.parse(result.output) else {
            RemoteLog.say("\(target.host) answered the check with text that is not facts: \(result.output.prefix(200))")
            throw RemoteFailure.noAnswer
        }
        return facts
    }

    static func result(_ host: String, _ fingerprint: String, _ facts: RemoteFacts, parentURL: String, builds: Set<String>) -> VerifyResult {
        let verification = RemoteVerify.run(facts: facts, fingerprint: fingerprint, agentBuilds: builds, parentURL: parentURL)
        return VerifyResult(host: host, fingerprint: fingerprint,
                            facts: .init(os: facts.os, arch: facts.arch, version: facts.version, chip: facts.chip, user: facts.user, home: facts.home, computerName: facts.hostname, cpuCores: facts.cpuCores, ramMb: facts.ramMb, diskFreeGb: facts.diskFreeGb),
                            requirements: verification.requirements, canAdd: verification.canAdd, isolation: verification.isolation, system: verification.system)
    }

    /// The parent's public key, for an operator who prefers to put it on the computer by hand instead of typing a password.
    func parentPublicKey() throws -> String { try ssh.parentKey().publicKey }

    private func record(_ actor: String, _ action: String, _ target: RemoteTarget, _ detail: [String: String]) {
        try? audit.record(actor: actor, action: action, target: "\(target.user)@\(target.host):\(target.port)", detail: detail, at: clock.now)
    }

    /// A refusal is audited against what the request named: the address it typed, or the machine it asked about (its record may be missing).
    private func recordRefusal(_ actor: String, _ target: RemoteLoginTarget, _ failure: RemoteFailure) {
        let named: String
        switch target {
        case .typed(let typed, _): named = "\(typed.user)@\(typed.host):\(typed.port)"
        case .stored(let machine): named = machine
        }
        try? audit.record(actor: actor, action: "remote.verify", target: named, detail: ["result": "\(failure)"], at: clock.now)
    }
}
