import Foundation
import MSCore
import RootCore
import RootStore

struct SshCredentials {
    let auth: SshAuth
    let environment: [String: String]
}

/// What both Connect and the installer need from SSH: which address may be used, the host keys we trust, the credentials (a password held in memory for one job, or a key opened in
/// a private ssh-agent), and running a script or sending a file on the other computer. Nothing here keeps a password.
final class RemoteSsh: @unchecked Sendable {
    struct Parts {
        let config: RootConfig
        let clock: Clock
        let keys: RemoteKeyStore
        let secrets: SecretBox
        let throttle: Throttle
    }

    let parts: Parts
    let pins: HostKeyPins
    private let agent = SshAgentHost()
    private let directory: String

    static let tryWindow: TimeInterval = 60
    static let scanSeconds: TimeInterval = 15
    static let parentKeyName = "parent"

    init(parts: Parts) {
        self.parts = parts
        directory = (parts.config.databasePath as NSString).deletingLastPathComponent + "/ssh"
        pins = HostKeyPins(path: directory + "/known_hosts")
    }

    func stop() { agent.stop() }

    // MARK: where, and whom to trust

    func allowedAddress(_ target: RemoteTarget) throws -> String {
        guard let address = HostResolver.ipv4(target.host) else { throw RemoteFailure.unreachable }
        guard RemoteTarget.allowed(address: address, allowLoopback: parts.config.remoteAllowLoopback, subnet: parts.config.scanSubnet) else { throw RemoteFailure.notAllowed }
        return address
    }

    /// Where an Agent on another computer finds the parent: its own loopback, through the SSH connection (see ParentUrl).
    var parentURL: String { ParentUrl.make(port: parts.config.agentListenPort) }

    func reversePort(for address: String) -> Int? { ParentUrl.reversePort(listenPort: parts.config.agentListenPort, target: address, ownAddresses: SubnetDetector.localAddresses()) }

    /// The address an Agent's first call will come from, or nil when it comes through a return path (see ParentUrl).
    func arrivalAddress(for address: String) -> String? { ParentUrl.arrivalAddress(target: address, ownAddresses: SubnetDetector.localAddresses()) }

    /// A few logins a minute on one computer: more would look like an attack on the network.
    func allowTry(_ target: RemoteTarget) throws {
        guard parts.throttle.allow("remote:\(target.host):\(target.port)", limit: parts.config.remoteTriesPerMinute, seconds: Self.tryWindow) else { throw RemoteFailure.tooManyTries }
    }

    func scanKey(_ target: RemoteTarget) async throws -> (line: String, fingerprint: String) {
        let result: SshResult
        do {
            result = try await SshProcess.run("/usr/bin/ssh-keyscan", ["-T", "5", "-p", String(target.port), "-t", "ed25519,ecdsa,rsa", target.host], timeout: Self.scanSeconds)
        } catch SshProcessFailure.missing {
            throw RemoteFailure.noSsh
        } catch {
            throw RemoteFailure.unreachable
        }
        guard let line = HostKeys.chooseKey(scanOutput: result.output), let fingerprint = HostKeys.fingerprint(ofKeyLine: line) else { throw RemoteFailure.noHostKey }
        return (line, fingerprint)
    }

    /// Which logins that computer accepts (["publickey", "password"] ...), or nil when it did not say. Only asks; nothing is tried and nothing is trusted.
    func loginMethods(_ target: RemoteTarget) async -> [String]? {
        guard let result = try? await SshProcess.run("/usr/bin/ssh", SshArguments.methodsProbe(target: target), timeout: Self.scanSeconds) else { return nil }
        return SshErrors.methods(in: result.errors)
    }

    /// Trusts a key the operator confirmed. A key that is already trusted is left as it is; a different one for the same host is refused.
    func trust(_ line: String) throws {
        switch pins.status(of: line) {
        case .same: return
        case .changed: throw RemoteFailure.hostKeyChanged
        case .new: try pins.pin(line)
        }
    }

    // MARK: credentials

    func credentials(_ login: RemoteLoginRequest.Login) async throws -> SshCredentials {
        switch login {
        case .password(let password):
            return SshCredentials(auth: .password, environment: ["SSH_ASKPASS": try askpass(), "SSH_ASKPASS_REQUIRE": "force", "METASERVICE_SSH_PASSWORD": password])
        case .parentKey:
            return try await keyCredentials(try parentKey())
        }
    }

    /// A key logs in through the private agent: the key is opened from its sealed form in memory and handed to ssh-add on its standard input.
    func keyCredentials(_ key: RemoteKey) async throws -> SshCredentials {
        try await agent.add(privateKey: try parts.secrets.open(key.privateSealed), name: key.name)
        return SshCredentials(auth: .key(path: try publicKeyFile(key)), environment: ["SSH_AUTH_SOCK": try agent.ensureRunning()])
    }

    func parentKey() throws -> RemoteKey {
        try key(named: Self.parentKeyName, comment: "metaservice-parent")
    }

    /// One key per machine, made when the machine is added. The private half is sealed before it is stored.
    func machineKey(_ machine: String) throws -> RemoteKey {
        try key(named: "machine:" + machine, comment: PlanScripts.keyMarker(machine))
    }

    /// A machine was removed or its install rolled back: its key goes too, including the agent's cached identity.
    func machineKeyRemove(_ machine: String) async throws {
        let name = "machine:" + machine
        if let key = try parts.keys.get(name) { try await agent.remove(publicKey: key.publicKey, name: name) }
        try parts.keys.remove(name)
    }

    private func key(named name: String, comment: String) throws -> RemoteKey {
        if let existing = try parts.keys.get(name) { return existing }
        let pair = OpenSshKey.generateEd25519(comment: comment)
        try parts.keys.addIfMissing(RemoteKey(name: name, publicKey: pair.publicKey, privateSealed: try parts.secrets.seal(pair.privateKey)), now: parts.clock.now)
        guard let stored = try parts.keys.get(name) else { throw RemoteFailure.noSsh }
        return stored
    }

    // MARK: running things there

    /// Runs a script on the other computer: one login, the script on its standard input.
    func run(_ script: String, on target: RemoteTarget, with credentials: SshCredentials, timeout: TimeInterval, reversePort: Int? = nil) async throws -> SshResult {
        try await ssh(target, credentials, command: ["sh", "-s"], input: Data(script.utf8), timeout: timeout, reversePort: reversePort)
    }

    /// Runs one command line on the other computer with `input` on its standard input and nothing else (no script is sent that way). Used for `sudo -S`, which reads its password there.
    func run(command: String, input: Data, on target: RemoteTarget, with credentials: SshCredentials, timeout: TimeInterval) async throws -> SshResult {
        try await ssh(target, credentials, command: [command], input: input, timeout: timeout)
    }

    /// Streams a local file into a file on the other computer (made private first). The path was checked to be plain, so it is safe in the remote command.
    func send(file localPath: String, to remotePath: String, on target: RemoteTarget, with credentials: SshCredentials, timeout: TimeInterval) async throws -> SshResult {
        guard let content = FileManager.default.contents(atPath: localPath) else { throw RemoteFailure.noAnswer }
        return try await ssh(target, credentials, command: ["umask 077; cat > " + Shell.quote(remotePath)], input: content, timeout: timeout)
    }

    private func ssh(_ target: RemoteTarget, _ credentials: SshCredentials, command: [String], input: Data, timeout: TimeInterval, reversePort: Int? = nil) async throws -> SshResult {
        let arguments = SshArguments.login(target: target, auth: credentials.auth, knownHosts: pins.path, command: command, reversePort: reversePort)
        do {
            return try await SshProcess.run("/usr/bin/ssh", arguments, input: input, environment: credentials.environment, timeout: timeout, maxOutput: 4 * 1_048_576)
        } catch SshProcessFailure.timedOut {
            throw RemoteFailure.timedOut
        } catch {
            throw RemoteFailure.noSsh
        }
    }

    // MARK: helper files

    /// A one-line helper that ssh runs to ask for the password: it only repeats an environment variable, so the password is never in a file or on a command line.
    private func askpass() throws -> String {
        let path = directory + "/askpass.sh"
        try ensureDirectory()
        guard !FileManager.default.isExecutableFile(atPath: path) else { return path }
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\nprintf '%s\\n' \"$METASERVICE_SSH_PASSWORD\"\n".utf8), attributes: [.posixPermissions: 0o700])
        return path
    }

    /// ssh is told which key to use by the public key's file; the private half comes from the agent. The public key is not a secret.
    private func publicKeyFile(_ key: RemoteKey) throws -> String {
        try ensureDirectory()
        let path = directory + "/" + key.name.replacingOccurrences(of: ":", with: "-") + ".pub"
        try Data((key.publicKey + "\n").utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        return path
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}
