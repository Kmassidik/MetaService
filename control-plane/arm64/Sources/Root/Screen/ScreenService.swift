import Foundation
import MSCore
import RootCore
import RootStore

enum ScreenFailure: Error {
    case machineNotFound
    case unreachable
    /// The machine answered that the screen cannot be used (off, or the permission is missing). The text is the machine's own plain explanation.
    case notReady(String)
    case refused(ScreenRefusal)
    /// The machine's own strict check refused the input (a position or key out of range, too many events).
    case badInput(String)
}

struct ScreenPicture {
    let contentType: String
    let data: Data
}

/// Screens opened from the panel: it keeps the open sessions, asks the machine's Agent for pictures and passes input to it, and writes every open, control and close to the audit log.
/// No picture and no key is ever kept or logged.
final class ScreenService: @unchecked Sendable {
    private let client: AgentClient
    private let audit: AuditStore
    private let clock: Clock
    private let lock = NSLock()
    private var book: ScreenSessionBook

    private static let pictureTypes: Set<String> = ["image/png", "image/jpeg"]

    init(client: AgentClient, audit: AuditStore, clock: Clock, book: ScreenSessionBook = ScreenSessionBook()) {
        self.client = client
        self.audit = audit
        self.clock = clock
        self.book = book
    }

    func status(machine: String) async throws -> [String: Any] {
        let reply = try await ask(machine, "GET", "/v1/screen")
        return reply.json ?? [:]
    }

    func open(machine: String, actor: String) async throws -> ScreenSession {
        let reported = try await status(machine: machine)
        guard reported["access"] as? String == "ready" else { throw ScreenFailure.notReady(reported["message"] as? String ?? "Screen control is not available on this computer.") }
        let session = try locked { try book.open(machine: machine, operatorName: actor, ticket: Tokens.random(bytes: 16), now: clock.now) }
        try audit.record(actor: actor, action: "screen.open", target: machine, at: clock.now)
        return session
    }

    func takeControl(ticket: String, actor: String, confirmed: Bool) throws -> ScreenSession {
        let session = try locked { try book.takeControl(ticket: ticket, operatorName: actor, confirmed: confirmed, now: clock.now) }
        try audit.record(actor: actor, action: "screen.control", target: session.machine, at: clock.now)
        return session
    }

    func picture(ticket: String, actor: String) async throws -> ScreenPicture {
        let session = try locked { try book.use(ticket: ticket, operatorName: actor, now: clock.now) }
        let reply = try await fetch(session.machine, "GET", "/v1/screen/frame", nil)
        guard reply.status == 200, let type = reply.contentType, Self.pictureTypes.contains(type) else { throw ScreenFailure.notReady("The screen cannot be read right now.") }
        return ScreenPicture(contentType: type, data: reply.data)
    }

    func send(ticket: String, actor: String, body: [String: Any]) async throws {
        let session = try locked { try book.use(ticket: ticket, operatorName: actor, now: clock.now) }
        guard session.mode == .control else { throw ScreenFailure.refused(.viewOnly) }
        let reply = try await fetch(session.machine, "POST", "/v1/screen/input", body)
        if reply.status == 400 { throw ScreenFailure.badInput("the input was refused as invalid") }
        guard reply.status == 204 else { throw ScreenFailure.notReady("The input was refused by that computer.") }
    }

    func close(ticket: String, actor: String) throws {
        guard let session = locked({ book.close(ticket: ticket, operatorName: actor) }) else { return }
        try audit.record(actor: actor, action: "screen.close", target: session.machine, at: clock.now)
    }

    /// A machine is going away: its screens close with it.
    func closeAll(machine: String) {
        _ = locked { book.closeAll(machine: machine) }
    }

    // MARK: pieces

    private func locked<T>(_ work: () throws -> T) rethrows -> T { try lock.withLock(work) }

    private func ask(_ machine: String, _ method: String, _ path: String) async throws -> AgentReply {
        do {
            return try await client.call(machine: machine, method: method, path: path)
        } catch AgentCallFailure.neverHeardFrom {
            throw ScreenFailure.machineNotFound
        } catch {
            throw ScreenFailure.unreachable
        }
    }

    private func fetch(_ machine: String, _ method: String, _ path: String, _ body: [String: Any]?) async throws -> (status: Int, contentType: String?, data: Data) {
        do {
            return try await client.fetch(machine: machine, method: method, path: path, body: body)
        } catch AgentCallFailure.neverHeardFrom {
            throw ScreenFailure.machineNotFound
        } catch {
            throw ScreenFailure.unreachable
        }
    }
}
