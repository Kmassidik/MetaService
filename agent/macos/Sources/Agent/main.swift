import Foundation
import Hummingbird
import AgentCore
import MSCore

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data("metaservice-agent: \(text)\n".utf8))
    exit(1)
}

/// A token file: it must exist, hold something, and be readable by its owner only.
func readToken(_ path: String) throws -> String {
    guard let raw = try? String(contentsOfFile: path, encoding: .utf8), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ConfigError(description: "no token in \(path); run `metaservice-agent enroll` first")
    }
    let mode = ((try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? NSNumber)?.intValue ?? 0o777
    guard mode & 0o077 == 0 else { throw ConfigError(description: "\(path) must be mode 600 (owner only)") }
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
}

func makeEngine(_ config: AgentConfig) throws -> Engine {
    guard config.engineName == "apple" else { return SimulatedEngine() }
    guard let path = ProcessContainerCLI.locate(config.containerPath) else { throw ConfigError(description: "the `container` program was not found; install Apple container or pass --container-path") }
    try FileManager.default.createDirectory(atPath: config.stateDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return AppleContainerEngine(cli: ProcessContainerCLI(path: path), records: RecordStore(path: config.stateDirectory + "/workloads.json"),
                                backupDirectory: config.backupDirectory ?? config.stateDirectory + "/backups", defaultImage: config.defaultImage)
}

/// The command ledger lives in a file (mode 600) next to the token, so a repeated command id still means "already done" after a restart.
func makeLedger(_ config: AgentConfig) -> CommandLedger {
    let path = config.stateDirectory + "/commands.json"
    let restored = (FileManager.default.contents(atPath: path).flatMap { try? JSONDecoder().decode([Command].self, from: $0) }) ?? []
    return CommandLedger(restored: restored, persist: { commands in
        guard let data = try? JSONEncoder().encode(commands) else { return }
        FileManager.default.createFile(atPath: path + ".tmp", contents: data, attributes: [.posixPermissions: 0o600])
        _ = try? FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: path + ".tmp"))
    })
}

func rootAddress(_ config: AgentConfig) -> URL? {
    guard let data = FileManager.default.contents(atPath: config.settingsFile), let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
    return object["root"].flatMap { try? RootLink.validated($0) }
}

func makeSupervisor(_ config: AgentConfig) -> ChatSupervisor? {
    guard let python = config.pythonPath ?? ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
    return ChatSupervisor(python: python, logPath: config.stateDirectory + "/chat.log")
}

/// When the Agent is told to stop, the chat it runs stops too.
func stopOnSignal(_ supervisor: ChatSupervisor?) {
    for signalNumber in [SIGTERM, SIGINT] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler { Task { await supervisor?.stop(); exit(0) } }
        source.resume()
        signalSources.append(source)
    }
}

nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []

func runAgent(_ config: AgentConfig) async throws {
    let commandToken = try readToken(config.commandTokenFile)
    let probe = await SystemProbe.measure()
    let budget = SpaceBudget(ramTotalMb: probe.specs.ramTotalMb, diskTotalGb: probe.specs.diskTotalGb, ramAllowanceMb: config.ramAllowanceMb, diskAllowanceGb: config.diskAllowanceGb,
                             reserveRamMb: config.reserveRamMb, reserveDiskGb: config.reserveDiskGb)
    let ledger = makeLedger(config)
    let engine = try makeEngine(config)
    let root = rootAddress(config)
    let machineToken = root == nil ? nil : try readToken(config.tokenFile)
    let supervisor = ProcessInfo.processInfo.environment["MS_NO_CHAT"] == nil ? makeSupervisor(config) : nil
    let installer = BundleInstaller(config: config, engine: engine, root: root, machineToken: machineToken, supervisor: supervisor)
    await installer.resume()
    stopOnSignal(supervisor)
    let service = AgentService(engine: engine, budget: budget, specs: probe.specs, agentVersion: AgentConfig.version, ledger: ledger, installer: installer,
                               osAvailableDiskGb: { SystemProbe.availableDiskGb() })
    let router = Router(context: AgentContext.self)
    router.add(middleware: SecurityHeadersMiddleware())
    router.add(middleware: ErrorMiddleware())
    router.add(middleware: TokenMiddleware(token: commandToken, badLimit: config.badTokenLimit))
    AgentRoutes(service: service).register(on: router)
    if let root, let machineToken {
        let heartbeat = Heartbeat(root: root, token: machineToken, service: service, agentPort: config.port, seconds: config.heartbeatSeconds)
        service.onChange = { heartbeat.beatSoon() }
        Task.detached { await heartbeat.run() }
    }
    let app = Application(router: router, configuration: .init(address: .hostname(config.bind, port: config.port)))
    try await app.runService()
}

do {
    let config = try AgentConfig.parse(Array(CommandLine.arguments.dropFirst()))
    switch config.command {
    case .run: try await runAgent(config)
    case .enroll(let root, let name, let tokenFile): try await Enroller.run(root: root, name: name, tokenFile: tokenFile, config: config)
    }
} catch {
    fail("\(error)")
}
