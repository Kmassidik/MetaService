import Foundation
import Hummingbird
import HTTPTypes
import AgentCore
import MSCore

struct ExternalService: Encodable, Equatable {
    let id: String
    let name: String
    let runtime: ExternalRuntime
    let kind: WorkloadKind
    let state: ExternalServiceState
    let image: String?
}

enum ExternalRuntime: String, Codable { case docker, apple }
enum ExternalServiceState: String, Codable { case running, stopped, unknown }

struct ExternalWarning: Encodable, Equatable {
    let runtime: ExternalRuntime
    let message: String
}

struct ExternalServiceList: Encodable, Equatable {
    let services: [ExternalService]
    let warnings: [ExternalWarning]
}

enum ExternalServiceAction: String {
    case start, stop, restart

    var commandType: CommandType {
        switch self {
        case .start: return .start
        case .stop: return .stop
        case .restart: return .restart
        }
    }
}

/// Docker is only inspected here. MetaService never creates or adopts its containers.
struct DockerCLI: ContainerCLI {
    let path: String

    static let searchPaths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"]

    static func locate() -> String? {
        searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func run(_ arguments: [String], timeout: TimeInterval, input: Data?) async throws -> Data {
        do {
            return try await CommandRunner.run(path, arguments, timeout: timeout, input: input)
        } catch CommandFailure.failed(let status, let errors) {
            throw EngineError.failed("docker \(arguments.first ?? "") exited with \(status): \(errors.suffix(300))")
        } catch CommandFailure.timedOut {
            throw EngineError.failed("docker \(arguments.first ?? "") took too long")
        } catch {
            throw EngineError.failed("docker \(arguments.first ?? "") could not run")
        }
    }
}

/// Reads external containers and changes only a target found by a fresh read. No discovery path prepares a runtime.
actor ExternalServices {
    private let docker: ContainerCLI?
    private let apple: ContainerCLI?
    private let records: RecordStore
    private let ledger: CommandLedger
    private static let timeout: TimeInterval = 30
    private static let maxErrorBytes = 300

    init(docker: ContainerCLI?, apple: ContainerCLI?, records: RecordStore, ledger: CommandLedger) {
        self.docker = docker
        self.apple = apple
        self.records = records
        self.ledger = ledger
    }

    func list() async -> ExternalServiceList {
        let managed = Set(records.all().keys.map(AppleContainer.name(for:)))
        let dockerBatch = await read(runtime: .docker, cli: docker, managed: managed)
        let appleBatch = await read(runtime: .apple, cli: apple, managed: managed)
        return ExternalServiceList(services: (dockerBatch.services + appleBatch.services).sorted { ($0.name, $0.id) < ($1.name, $1.id) },
                                   warnings: dockerBatch.warnings + appleBatch.warnings)
    }

    func change(commandId: String, id: String, action: ExternalServiceAction) async throws -> Command {
        if let existing = ledger.find(commandId) { return existing }
        let fresh = await list()
        guard let target = fresh.services.first(where: { $0.id == id }) else {
            guard let warning = fresh.warnings.first(where: { id.hasPrefix($0.runtime.rawValue + ":") }) else { throw AgentError.notFound }
            return failed(commandId: commandId, action: action, message: warning.message)
        }
        var command = Command(commandId: commandId, type: action.commandType, state: .running, workloadId: nil)
        ledger.record(command)
        do {
            try await execute(action, target: target)
            command.state = .succeeded
            command.result = ["state": action == .stop ? ExternalServiceState.stopped.rawValue : ExternalServiceState.running.rawValue]
        } catch {
            command.state = .failed
            command.result = ["error": Self.boundedError(error)]
        }
        ledger.record(command)
        return command
    }

    private func failed(commandId: String, action: ExternalServiceAction, message: String) -> Command {
        let command = Command(commandId: commandId, type: action.commandType, state: .failed, workloadId: nil, result: ["error": Self.bounded(message)])
        ledger.record(command)
        return command
    }

    private func read(runtime: ExternalRuntime, cli: ContainerCLI?, managed: Set<String>) async -> ExternalServiceList {
        guard let cli else { return ExternalServiceList(services: [], warnings: []) }
        do {
            let data = try await cli.run(Self.listArguments(runtime), timeout: Self.timeout)
            let services = try Self.parse(runtime, data: data).filter { !managed.contains($0.name) }
            return ExternalServiceList(services: services, warnings: [])
        } catch {
            return ExternalServiceList(services: [], warnings: [ExternalWarning(runtime: runtime, message: Self.boundedError(error))])
        }
    }

    private func execute(_ action: ExternalServiceAction, target: ExternalService) async throws {
        let nativeId = String(target.id.dropFirst(target.runtime.rawValue.count + 1))
        let cli = target.runtime == .docker ? docker : apple
        guard let cli else { throw EngineError.failed("the \(target.runtime.rawValue) tool is no longer available") }
        if action != .restart || target.runtime == .docker {
            _ = try await cli.run([action.rawValue, nativeId], timeout: Self.timeout)
            return
        }
        _ = try await cli.run([ExternalServiceAction.stop.rawValue, nativeId], timeout: Self.timeout)
        _ = try await cli.run([ExternalServiceAction.start.rawValue, nativeId], timeout: Self.timeout)
    }

    private static func listArguments(_ runtime: ExternalRuntime) -> [String] {
        switch runtime {
        case .docker: return ["ps", "--all", "--no-trunc", "--format", "{{json .}}"]
        case .apple: return AppleContainer.listAll
        }
    }

    private static func parse(_ runtime: ExternalRuntime, data: Data) throws -> [ExternalService] {
        switch runtime {
        case .docker: return try parseDocker(data)
        case .apple: return try parseApple(data)
        }
    }

    private static func parseDocker(_ data: Data) throws -> [ExternalService] {
        let lines = data.split(separator: 0x0A).prefix(5000)
        return try lines.compactMap { line in
            guard !line.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) else { return nil }
            let object = try JSONSerialization.jsonObject(with: line)
            guard let item = object as? [String: Any], let id = item["ID"] as? String, !id.isEmpty,
                  let name = (item["Names"] as? String) ?? (item["Name"] as? String), !name.isEmpty else {
                throw EngineError.failed("docker returned an unreadable container list")
            }
            let rawState = (item["State"] as? String)?.lowercased() ?? "unknown"
            return ExternalService(id: "docker:\(id)", name: name, runtime: .docker, kind: .container, state: dockerState(rawState), image: item["Image"] as? String)
        }
    }

    private static func parseApple(_ data: Data) throws -> [ExternalService] {
        let parsed = try JSONSerialization.jsonObject(with: data)
        let items = (parsed as? [[String: Any]]) ?? (parsed as? [String: Any]).map { [$0] }
        guard let items else { throw EngineError.failed("container returned an unreadable container list") }
        return items.prefix(5000).compactMap { item in
            let configuration = item["configuration"] as? [String: Any]
            guard let name = (configuration?["id"] as? String) ?? (item["name"] as? String) ?? (item["id"] as? String), !name.isEmpty else { return nil }
            let nativeId = (item["uuid"] as? String) ?? (item["instanceId"] as? String) ?? (configuration == nil ? nil : item["id"] as? String) ?? name
            let status = item["status"] as? [String: Any]
            let rawState = ((status?["state"] as? String) ?? (item["status"] as? String) ?? "unknown").lowercased()
            let imageObject = configuration?["image"] as? [String: Any]
            let image = (imageObject?["reference"] as? String) ?? (item["image"] as? String)
            return ExternalService(id: "apple:\(nativeId)", name: name, runtime: .apple, kind: .vm, state: appleState(rawState), image: image)
        }
    }

    private static func dockerState(_ raw: String) -> ExternalServiceState {
        switch raw {
        case "running": return .running
        case "created", "exited", "dead", "stopped": return .stopped
        default: return .unknown
        }
    }

    private static func appleState(_ raw: String) -> ExternalServiceState {
        switch raw {
        case "running": return .running
        case "created", "exited", "stopped": return .stopped
        default: return .unknown
        }
    }

    private static func boundedError(_ error: Error) -> String {
        switch error {
        case EngineError.failed(let message), EngineError.notReady(let message): return bounded(message)
        default: return bounded(String(describing: error))
        }
    }

    private static func bounded(_ message: String) -> String {
        let line = message.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
        guard line.utf8.count > maxErrorBytes else { return line }
        var result = ""
        var bytes = 0
        for character in line {
            guard bytes + character.utf8.count <= maxErrorBytes else { break }
            result.append(character)
            bytes += character.utf8.count
        }
        return result
    }
}

struct ExternalServicesRoutes {
    let service: ExternalServices

    func register(on router: Router<AgentContext>) {
        router.get("/v1/external-services") { _, _ in try Json.response(await self.service.list()) }
        router.post("/v1/external-services/{id}/start") { request, context in try await self.change(request, context, .start) }
        router.post("/v1/external-services/{id}/stop") { request, context in try await self.change(request, context, .stop) }
        router.post("/v1/external-services/{id}/restart") { request, context in try await self.change(request, context, .restart) }
    }

    private func change(_ request: Request, _ context: AgentContext, _ action: ExternalServiceAction) async throws -> Response {
        guard let id = context.parameters.get("id"), !id.isEmpty else { throw ApiFailure.notFound }
        let command = try await service.change(commandId: try AgentRoutes.commandId(request), id: id, action: action)
        return try AgentRoutes.accepted(command)
    }
}
