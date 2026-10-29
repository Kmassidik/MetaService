import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

private struct ExternalKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct ExternalServiceList: Codable {
    let services: [ExternalServiceRecord]
    let warnings: [ExternalServiceWarning]

    private enum CodingKeys: String, CodingKey { case services, warnings }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ExternalKey.self)
        guard Set(raw.allKeys.map { $0.stringValue }) == ["services", "warnings"] else { throw ExternalReplyError.invalid }
        let box = try decoder.container(keyedBy: CodingKeys.self)
        services = try box.decode([ExternalServiceRecord].self, forKey: .services)
        warnings = try box.decode([ExternalServiceWarning].self, forKey: .warnings)
        guard services.count <= 256, warnings.count <= 12 else { throw ExternalReplyError.invalid }
    }
}

struct ExternalServiceRecord: Codable {
    let id: String
    let name: String
    let runtime: String
    let kind: String
    let state: String
    let image: String?

    private enum CodingKeys: String, CodingKey { case id, name, runtime, kind, state, image }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ExternalKey.self)
        let keys = Set(raw.allKeys.map { $0.stringValue })
        guard Self.requiredKeys.isSubset(of: keys), keys.isSubset(of: Self.allowedKeys) else { throw ExternalReplyError.invalid }
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id)
        name = try box.decode(String.self, forKey: .name)
        runtime = try box.decode(String.self, forKey: .runtime)
        kind = try box.decode(String.self, forKey: .kind)
        state = try box.decode(String.self, forKey: .state)
        if box.contains(.image) {
            image = try box.decode(String.self, forKey: .image)
        } else {
            image = nil
        }
        guard Self.validText(name, max: 128), ["vm", "container"].contains(kind), ["running", "stopped", "unknown"].contains(state),
              ExternalServiceId.isValid(id, runtime: runtime), image.map({ Self.validText($0, max: 256) }) ?? true else { throw ExternalReplyError.invalid }
    }

    private static let requiredKeys: Set<String> = ["id", "name", "runtime", "kind", "state"]
    private static let allowedKeys: Set<String> = ["id", "name", "runtime", "kind", "state", "image"]
    private static func validText(_ text: String, max: Int) -> Bool {
        !text.isEmpty && text.count <= max
    }
}

struct ExternalServiceWarning: Codable {
    let runtime: String
    let message: String

    private enum CodingKeys: String, CodingKey { case runtime, message }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ExternalKey.self)
        guard Set(raw.allKeys.map { $0.stringValue }) == ["runtime", "message"] else { throw ExternalReplyError.invalid }
        let box = try decoder.container(keyedBy: CodingKeys.self)
        runtime = try box.decode(String.self, forKey: .runtime)
        message = try box.decode(String.self, forKey: .message)
        guard ["docker", "incus", "apple"].contains(runtime), !message.isEmpty, message.count <= 300 else { throw ExternalReplyError.invalid }
    }
}

private enum ExternalReplyError: Error { case invalid }

enum ExternalServiceId {
    private static let runtimes = ["docker", "incus", "apple"]
    private static let nativeCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")

    static func isValid(_ id: String, runtime expected: String? = nil) -> Bool {
        guard let colon = id.firstIndex(of: ":") else { return false }
        let runtime = String(id[..<colon])
        let native = id[id.index(after: colon)...]
        guard runtimes.contains(runtime), expected.map({ $0 == runtime }) ?? true else { return false }
        guard !native.isEmpty, native.utf8.count <= 128, let first = native.first, first.isLetter || first.isNumber else { return false }
        return native.allSatisfy(nativeCharacters.contains)
    }
}

/// Live discovery and explicit lifecycle for services the managed workload store does not own.
final class ExternalServicesService: @unchecked Sendable {
    enum Action: String { case start, stop, restart }

    private static let helperTimeoutSeconds: TimeInterval = 10
    private static let listPath = "/v1/external-services"
    private let machines: MachineStore
    private let commands: CommandStore
    private let audit: AuditStore
    private let client: AgentClient
    private let clock: Clock

    init(machines: MachineStore, commands: CommandStore, audit: AuditStore, client: AgentClient, clock: Clock) {
        self.machines = machines
        self.commands = commands
        self.audit = audit
        self.client = client
        self.clock = clock
    }

    func list(machine: String) async throws -> ExternalServiceList {
        try requireMachine(machine)
        return try await discover(machine)
    }

    func act(actor: String, machine: String, externalId: String, action: Action) async throws -> CommandRow {
        try requireMachine(machine)
        guard ExternalServiceId.isValid(externalId) else { throw ApiFailure.notFound }
        let found = try await discover(machine)
        guard found.services.contains(where: { $0.id == externalId }) else { throw ApiFailure.notFound }
        let id = Self.newCommandId()
        try commands.create(id: id, machine: machine, workloadId: nil, type: action.rawValue, params: ["external_id": externalId], actor: actor, now: clock.now)
        try audit.record(actor: actor, action: "external_service.\(action.rawValue)", target: machine,
                         detail: ["external_id": externalId, "command": id], at: clock.now)
        return try await send(id, machine: machine, externalId: externalId, action: action)
    }

    func resume() {
        for command in (try? commands.unfinished()) ?? [] where Self.owns(command) { follow(command.id, machine: command.machine) }
    }

    static func owns(_ command: CommandRow) -> Bool {
        command.workloadId == nil && command.params["external_id"] != nil && ["start", "stop", "restart"].contains(command.type)
    }

    private func requireMachine(_ id: String) throws {
        do {
            let machine = try machines.get(id: id, now: clock.now)
            guard machine.state != "offline" else { throw Self.unreachable }
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
    }

    private func discover(_ machine: String) async throws -> ExternalServiceList {
        guard let reply = try? await client.call(machine: machine, method: "GET", path: Self.listPath, timeout: Self.helperTimeoutSeconds) else { throw Self.unreachable }
        guard reply.status != 404 else { throw ApiFailure.notFound }
        guard reply.status == 200, let list = try? JSONDecoder().decode(ExternalServiceList.self, from: reply.data) else { throw Self.unreachable }
        return list
    }

    private func send(_ id: String, machine: String, externalId: String, action: Action) async throws -> CommandRow {
        let reply: AgentReply
        do {
            reply = try await client.call(machine: machine, method: "POST", path: "\(Self.listPath)/\(externalId)/\(action.rawValue)", body: nil, commandId: id)
        } catch {
            try finish(id, state: "failed", result: ["error": "the machine could not be reached"])
            throw Self.unreachable
        }
        guard reply.status == 202 else { throw try refused(id, reply) }
        try commands.update(id: id, state: "running", result: nil, now: clock.now)
        follow(id, machine: machine)
        return try commands.get(id)!
    }

    private func refused(_ id: String, _ reply: AgentReply) throws -> Error {
        let detail = reply.json?["error"] as? [String: Any]
        let message = detail?["message"] as? String ?? "the machine refused"
        try finish(id, state: "failed", result: ["error": HelperFailureText.cleanResult(["error": message])["error"] ?? "the machine refused"])
        guard reply.status != 404 else { return ApiFailure.notFound }
        return ApiFailure(status: .badGateway, code: "machine_refused", message: "the machine refused the request")
    }

    private func follow(_ id: String, machine: String) {
        Task.detached { [self] in
            var silent = 0
            for _ in 0..<OrderFollowing.giveUpAfterSeconds {
                try? await Task.sleep(nanoseconds: UInt64(OrderFollowing.pollSeconds) * 1_000_000_000)
                guard let reply = try? await client.call(machine: machine, method: "GET", path: "/v1/commands/\(id)") else {
                    silent += 1
                    guard silent < OrderFollowing.lostContactAfterPolls else { return lost(id, "lost contact with the machine") }
                    continue
                }
                silent = 0
                guard let state = reply.json?["state"] as? String, ["succeeded", "failed"].contains(state) else { continue }
                return done(id, state: state, result: reply.json?["result"] as? [String: Any])
            }
            lost(id, "gave up waiting")
        }
    }

    private func done(_ id: String, state: String, result: [String: Any]?) {
        let text = (result ?? [:]).compactMapValues { $0 as? String }
        try? finish(id, state: state, result: HelperFailureText.cleanResult(text))
    }

    private func lost(_ id: String, _ why: String) {
        try? finish(id, state: "failed", result: ["error": why])
    }

    private func finish(_ id: String, state: String, result: [String: String]) throws {
        try commands.update(id: id, state: state, result: result, now: clock.now)
        guard let row = try commands.get(id) else { return }
        try audit.record(actor: "root", action: "external_service.\(row.type)_\(state)", target: row.machine,
                         detail: ["command": id].merging(result) { $1 }, at: clock.now)
    }

    private static var unreachable: ApiFailure {
        ApiFailure(status: .badGateway, code: "machine_unreachable", message: "the machine could not be reached")
    }

    private static func newCommandId() -> String {
        "rc-" + Tokens.random(bytes: 9).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(12)
    }
}
