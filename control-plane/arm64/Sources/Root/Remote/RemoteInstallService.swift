import CryptoKit
import Foundation
import MSCore
import RootCore
import RootStore

struct PlanPreview: Encodable {
    struct Step: Encodable { let id: String, label: String, changes: [String] }
    let box: String
    let level: String
    let steps: [Step]
    let notes: [String]
}

/// Add machine for another computer: carries out the plan over SSH, one step after the other, and takes everything away again if a step fails. The operator watches the steps as
/// they happen. The password (if one was used) lives only in this job and is forgotten when it ends. One install runs at a time.
final class RemoteInstallService: @unchecked Sendable {
    struct Parts {
        let config: RootConfig
        let clock: Clock
        let ssh: RemoteSsh
        let machines: MachineStore
        let enrollments: EnrollmentStore
        let audit: AuditStore
        let remoteMachines: RemoteMachineStore
        let settings: MachineSettingsStore
        let chatAccess: ChatAccessStore
        let tunnels: TunnelSupervisor
    }

    /// Everything a running install knows once the computer was checked again.
    private struct Context {
        let target: RemoteTarget
        let credentials: SshCredentials
        let plan: InstallPlan
        let before: PlanScripts.BeforeFacts
        let fingerprint: String
        let binary: (path: String, size: Int, sha256: String)
        let token: String
        /// The computer's address, which is what the machine list shows (the Agent itself reports through the tunnel, from loopback).
        let address: String
    }

    let parts: Parts
    private let lock = NSLock()
    private var jobs: [String: InstallJob] = [:]
    private var active: String?

    private static let stepSeconds: TimeInterval = 60
    private static let sendSeconds: TimeInterval = 300
    private static let onlineSeconds = 60
    private static let defaultSteps: [(String, String)] = [("check", "Check the computer again"), ("folder", "Make the box folder"), ("agent", "Copy the MetaService program"),
                                                           ("enroll", "Enroll it with the parent"), ("start", "Start the program")]

    init(parts: Parts) { self.parts = parts }

    func job(_ id: String) -> InstallJob? { lock.withLock { jobs[id] } }

    // MARK: what will change

    func plan(_ request: PlanRequest) throws -> PlanPreview {
        let target = try RemoteTarget(host: request.host, user: "probe")
        let address = try parts.ssh.allowedAddress(target)
        let plan = try Self.makePlan(request.choices, home: request.home, isMac: request.isMac, rootURL: parts.ssh.parentURL, reversePort: parts.ssh.reversePort(for: address), config: parts.config, binarySize: nil)
        return PlanPreview(box: plan.options.box, level: plan.options.level.rawValue, steps: plan.steps.map { .init(id: $0.id, label: $0.label, changes: $0.changes) },
                           notes: ["Nothing that already exists on that computer is modified or removed.", "If any step fails, everything added so far is taken away again."])
    }

    private static func makePlan(_ choices: InstallChoices, home: String, isMac: Bool, rootURL: String, reversePort: Int?, config: RootConfig, binarySize: Int?) throws -> InstallPlan {
        do {
            let engine = config.remoteEngine ?? (isMac ? "apple" : "incus")
            var options = try choices.options(home: home, engine: engine, rootURL: rootURL)
            options.reversePort = reversePort
            return try InstallPlan.make(options, agentSize: binarySize)
        } catch RemoteInstallError.notAvailable(let why) {
            throw RemoteFailure.badOptions(why)
        } catch {
            throw RemoteFailure.badOptions("the name, a path or the port is not valid")
        }
    }

    // MARK: start

    func start(_ request: RemoteAddRequest, actor: String) throws -> String {
        let name = request.choices.name
        guard (try? parts.machines.get(id: name, now: parts.clock.now)) == nil, (try? parts.remoteMachines.get(name)) == nil else { throw RemoteFailure.machineExists }
        let id = "ri-" + Tokens.random(bytes: 6).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(10)
        var steps = Self.defaultSteps.map { InstallStep(id: $0.0, label: $0.1) }
        if request.choices.installKey { steps.append(InstallStep(id: "key", label: "Allow the parent's tunnel")) }
        steps.append(InstallStep(id: "manifest", label: "Write the record"))
        if request.choices.installKey { steps.append(InstallStep(id: "tunnel", label: "Open the tunnel to it")) }
        steps.append(InstallStep(id: "online", label: "Wait for the machine to report in"))
        try lock.withLock {
            guard active == nil else { throw RemoteFailure.installRunning }
            active = id
            jobs[id] = InstallJob(id: id, name: name, state: .running, steps: steps, error: nil, warning: nil)
        }
        try? parts.audit.record(actor: actor, action: "remote.install", target: "\(request.login.target.user)@\(request.login.target.host):\(request.login.target.port)", detail: ["machine": name], at: parts.clock.now)
        Task.detached { [self] in await run(id, request, actor: actor) }
        return id
    }

    private func run(_ id: String, _ request: RemoteAddRequest, actor: String) async {
        var added = Added()
        var context: Context?
        do {
            let checked = try await step(id, "check") { try await check(request) }
            context = checked
            try await carryOut(id, checked, request, &added)
            if added.key != nil { try await step(id, "tunnel") { try await openTunnel(request.choices.name) } }
            try await step(id, "online") { try await waitUntilOnline(request.choices.name) }
            finish(id, .done, error: nil)
        } catch {
            let undone = await rollBack(context, request.choices.name, added)
            finish(id, .failed, error: Self.explain(error) + undone)
        }
    }

    /// What has been added so far, so a failure can take exactly that away.
    private struct Added {
        var boxStarted = false
        var key: RemoteKey?
        var recorded = false
    }

    // MARK: the check

    private func check(_ request: RemoteAddRequest) async throws -> (detail: String, context: Context) {
        let login = request.login
        let target = login.target
        let address = try parts.ssh.allowedAddress(target)
        try parts.ssh.allowTry(target)
        let key = try await parts.ssh.scanKey(target)
        guard key.fingerprint == login.fingerprint else { throw RemoteFailure.fingerprintMismatch }
        try parts.ssh.trust(key.line)
        let credentials = try await parts.ssh.credentials(login.login)
        let facts = try await RemoteService.readFacts(parts.ssh, target, credentials)
        let url = parts.ssh.parentURL
        let reversePort = parts.ssh.reversePort(for: address)
        let builds = AgentBuilds.available(config: parts.config)
        let verification = RemoteService.result(target.host, key.fingerprint, facts, parentURL: url, builds: Set(builds.keys))
        guard verification.canAdd else { throw InstallFailure("the computer no longer passes the check: " + (verification.requirements.first { !$0.optional && !$0.ok }?.detail ?? "see Connect")) }
        guard let path = builds[facts.agentBuild], let content = FileManager.default.contents(atPath: path) else { throw InstallFailure("there is no MetaService program for \(facts.agentBuild)") }
        let plan = try Self.makePlan(request.choices, home: facts.home, isMac: facts.isMac, rootURL: url, reversePort: reversePort, config: parts.config, binarySize: content.count)
        let before = try await preflight(plan.options, target, credentials)
        // Through the return path the Agent arrives from loopback, so the token cannot be pinned to the computer's address; it is still used once, within minutes, over that SSH connection.
        let token = try parts.enrollments.create(machineName: plan.options.name, expectedIp: reversePort == nil ? address : nil, now: parts.clock.now).token
        let sha = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        return ("\(verification.system). The box goes to \(plan.options.box).",
                Context(target: target, credentials: credentials, plan: plan, before: before, fingerprint: key.fingerprint, binary: (path, content.count, sha), token: token, address: address))
    }

    private func step(_ id: String, _ stepId: String, _ work: () async throws -> (detail: String, context: Context)) async throws -> Context {
        mark(id, stepId, .running, nil)
        do {
            let done = try await work()
            mark(id, stepId, .done, done.detail)
            return done.context
        } catch {
            mark(id, stepId, .failed, Self.explain(error))
            throw error
        }
    }

    private func step(_ id: String, _ stepId: String, _ work: () async throws -> String) async throws {
        mark(id, stepId, .running, nil)
        do {
            mark(id, stepId, .done, try await work())
        } catch {
            mark(id, stepId, .failed, Self.explain(error))
            throw error
        }
    }

    private func preflight(_ options: RemoteInstallOptions, _ target: RemoteTarget, _ credentials: SshCredentials) async throws -> PlanScripts.BeforeFacts {
        let result = try await parts.ssh.run(PlanScripts.beforeScript(options), on: target, with: credentials, timeout: Self.stepSeconds)
        try Self.require(result, "the check before the install")
        return PlanScripts.BeforeFacts.parse(result.output)
    }

    // MARK: the steps

    private func carryOut(_ id: String, _ context: Context, _ request: RemoteAddRequest, _ added: inout Added) async throws {
        let options = context.plan.options
        for planned in context.plan.steps {
            switch planned.id {
            case "folder": added.boxStarted = true; try await step(id, "folder") { try await runScript(planned, context); return "Made \(options.box)" }
            case "agent": try await step(id, "agent") { try await sendProgram(context) }
            case "enroll": try await step(id, "enroll") { try await runScript(planned, context); try parts.settings.save(options.settings, machine: options.name); return "Enrolled as \(options.name)" }
            case "start": try await step(id, "start") { try await startProgram(planned, context) }
            case "key": try await step(id, "key") { added.key = try await addKey(planned, context); return "Added one line, marked \(PlanScripts.keyMarker(options.name))" }
            default: try await step(id, "manifest") { try await runScript(planned, context); try record(context, added.key); added.recorded = true; return "Wrote \(options.box)/manifest.json" }
            }
        }
    }

    private func runScript(_ planned: PlannedStep, _ context: Context, keyLine: String? = nil) async throws {
        let options = context.plan.options
        let manifest = PlanScripts.manifest(options, createdAt: ISO8601DateFormatter().string(from: parts.clock.now), before: context.before)
        let script = try PlanScripts.script(planned.operations, enrollToken: context.token, keyLine: keyLine, manifest: manifest)
        // Only the enrollment needs the way back to the parent; the program reports through the tunnel that the next steps open.
        let reversePort = planned.id == "enroll" ? options.reversePort : nil
        let result = try await parts.ssh.run(script, on: context.target, with: context.credentials, timeout: Self.stepSeconds, reversePort: reversePort)
        try Self.require(result, planned.label)
    }

    private func sendProgram(_ context: Context) async throws -> String {
        let path = context.plan.options.box + "/bin/" + InstallPlan.programName
        let sent = try await parts.ssh.send(file: context.binary.path, to: path, on: context.target, with: context.credentials, timeout: Self.sendSeconds)
        try Self.require(sent, "copying the program")
        let command = "umask 077; chmod 700 \(Shell.quote(path)); if command -v shasum >/dev/null 2>&1; then shasum -a 256 \(Shell.quote(path)); else sha256sum \(Shell.quote(path)); fi\n"
        let checked = try await parts.ssh.run(command, on: context.target, with: context.credentials, timeout: Self.stepSeconds)
        try Self.require(checked, "checking the program")
        guard checked.output.split(separator: " ").first.map(String.init) == context.binary.sha256 else { throw InstallFailure("the program that arrived is not the one that was sent (its checksum is different)") }
        return "Copied \(context.binary.size / 1_048_576) MB; the checksum matches."
    }

    private func startProgram(_ planned: PlannedStep, _ context: Context) async throws -> String {
        try await runScript(planned, context)
        let box = context.plan.options.box
        let alive = "cd \(Shell.quote(box)) && sleep 2 && if kill -0 \"$(cat state/agent.pid)\" 2>/dev/null; then echo alive; else echo dead; tail -n 5 logs/agent.log; fi\n"
        let result = try await parts.ssh.run(alive, on: context.target, with: context.credentials, timeout: Self.stepSeconds)
        guard result.output.hasPrefix("alive") else { throw InstallFailure("the program stopped right after it started: " + String(result.output.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)) }
        return "Running; it listens only on 127.0.0.1:\(context.plan.options.agentPort) of that computer."
    }

    /// Makes this machine's own key, and adds its restricted line. The private half is sealed and stored; the other computer only ever gets the public one.
    private func addKey(_ planned: PlannedStep, _ context: Context) async throws -> RemoteKey {
        let key = try parts.ssh.machineKey(context.plan.options.name)
        try await runScript(planned, context, keyLine: PlanScripts.keyLine(publicKey: key.publicKey, options: context.plan.options))
        return key
    }

    private func record(_ context: Context, _ key: RemoteKey?) throws {
        let options = context.plan.options
        let file = key == nil ? nil : options.sshDirectory + "/authorized_keys"
        try parts.remoteMachines.save(RemoteMachine(machine: options.name, host: context.target.host, sshPort: context.target.port, sshUser: context.target.user, fingerprint: context.fingerprint,
                                                    level: options.level.rawValue, box: options.box, sshDirectory: options.sshDirectory, agentPort: options.agentPort, engine: options.engine,
                                                    keyName: key?.name, keyFile: file, keyMarker: key == nil ? nil : PlanScripts.keyMarker(options.name),
                                                    keyFileCreated: key != nil && !context.before.keyFileExisted, sshDirCreated: key != nil && !context.before.sshDirExisted), now: parts.clock.now)
        try parts.machines.setIp(id: options.name, ip: context.address)
    }

    private func openTunnel(_ name: String) async throws -> String {
        guard let record = try parts.remoteMachines.get(name) else { throw InstallFailure("the machine was not recorded") }
        parts.tunnels.ensure(record)
        guard await parts.tunnels.waitUntilConnected(name, seconds: 20) else { throw InstallFailure("MetaService was installed, but the tunnel to it did not open. Check that SSH to that computer still works, or remove the machine and try again.") }
        return "Open: commands for this machine go through an SSH tunnel to 127.0.0.1:\(record.agentPort) there."
    }

    private func waitUntilOnline(_ name: String) async throws -> String {
        for _ in 0..<Self.onlineSeconds {
            if let machine = try? parts.machines.get(id: name, now: parts.clock.now), machine.state != "offline" { return "The machine reported in." }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw InstallFailure("MetaService was installed, but the machine did not report in within \(Self.onlineSeconds) seconds. Look at logs/agent.log in its box, or remove the machine and try again.")
    }

    // MARK: failure

    /// Takes away what the failed install added. A machine that finished its install (even if it never reported in) is kept: the operator can remove it from the dashboard.
    private func rollBack(_ context: Context?, _ name: String, _ added: Added) async -> String {
        guard let context, added.boxStarted, !added.recorded else { return "" }
        let options = context.plan.options
        try? parts.machines.remove(id: name)
        try? parts.settings.remove(machine: name)
        let key = added.key.map { _ in PlanScripts.RemovedKey(file: options.sshDirectory + "/authorized_keys", marker: PlanScripts.keyMarker(name), fileCreated: !context.before.keyFileExisted, directoryCreated: !context.before.sshDirExisted) }
        let script = PlanScripts.removeScript(box: options.box, key: key, rollingBack: true)
        guard let result = try? await parts.ssh.run(script, on: context.target, with: context.credentials, timeout: Self.stepSeconds), result.status == 0 else {
            return " Taking back what was added did not work: remove the folder \(options.box) on that computer by hand."
        }
        try? parts.ssh.machineKeyRemove(name)
        return " Everything that was added has been taken away again."
    }

    // MARK: bookkeeping

    private func mark(_ id: String, _ stepId: String, _ state: InstallState, _ detail: String?) {
        lock.withLock {
            guard var job = jobs[id], let index = job.steps.firstIndex(where: { $0.id == stepId }) else { return }
            job.steps[index].state = state
            job.steps[index].detail = detail
            jobs[id] = job
        }
    }

    private func finish(_ id: String, _ state: InstallState, error: String?) {
        lock.withLock {
            jobs[id]?.state = state
            jobs[id]?.error = error
            active = nil
        }
    }

    /// A script that stopped: what it said after "ms-error:" if it said anything, otherwise the end of its error text.
    private static func require(_ result: SshResult, _ what: String) throws {
        guard result.status != 0 else { return }
        if let line = result.output.split(separator: "\n").first(where: { $0.hasPrefix("ms-error:") }) { throw InstallFailure(String(line.dropFirst("ms-error:".count)).trimmingCharacters(in: .whitespaces)) }
        let failure = RemoteFailure.fromSsh(result.errors, status: result.status)
        guard case .noAnswer = failure else { throw failure }
        throw InstallFailure("\(what) did not work: " + String(result.errors.suffix(200)).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func explain(_ error: Error) -> String {
        if let failure = error as? RemoteFailure { return failure.api.message }
        return InstallService.explain(error)
    }
}
