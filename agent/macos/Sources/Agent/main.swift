import Foundation
import Hummingbird
import AgentCore
import MSCore

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data("metaservice-agent: \(text)\n".utf8))
    exit(1)
}

func readToken(_ config: AgentConfig) throws -> String {
    guard let raw = try? String(contentsOfFile: config.tokenFile, encoding: .utf8), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ConfigError(description: "no machine token in \(config.tokenFile); run `metaservice-agent enroll` first")
    }
    let mode = ((try? FileManager.default.attributesOfItem(atPath: config.tokenFile)[.posixPermissions]) as? NSNumber)?.intValue ?? 0o777
    guard mode & 0o077 == 0 else { throw ConfigError(description: "\(config.tokenFile) must be mode 600 (owner only)") }
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
}

func makeEngine(_ config: AgentConfig) throws -> Engine {
    guard config.engineName == "simulated" else { throw ConfigError(description: "the apple engine is not built yet") }
    return SimulatedEngine()
}

func rootAddress(_ config: AgentConfig) -> URL? {
    guard let data = FileManager.default.contents(atPath: config.settingsFile), let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
    return object["root"].flatMap { try? RootLink.validated($0) }
}

func runAgent(_ config: AgentConfig) async throws {
    let token = try readToken(config)
    let probe = await SystemProbe.measure()
    let budget = SpaceBudget(ramTotalMb: probe.specs.ramTotalMb, diskTotalGb: probe.specs.diskTotalGb, ramAllowanceMb: config.ramAllowanceMb, diskAllowanceGb: config.diskAllowanceGb,
                             reserveRamMb: config.reserveRamMb, reserveDiskGb: config.reserveDiskGb)
    let service = AgentService(engine: try makeEngine(config), budget: budget, specs: probe.specs, agentVersion: AgentConfig.version, osAvailableDiskGb: { SystemProbe.availableDiskGb() })
    let router = Router(context: AgentContext.self)
    router.add(middleware: SecurityHeadersMiddleware())
    router.add(middleware: ErrorMiddleware())
    router.add(middleware: TokenMiddleware(token: token, badLimit: config.badTokenLimit))
    AgentRoutes(service: service).register(on: router)
    if let root = rootAddress(config) { Task.detached { await Heartbeat(root: root, token: token, service: service).run() } }
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
