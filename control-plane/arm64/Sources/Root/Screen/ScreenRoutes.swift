import Foundation
import Hummingbird
import HTTPTypes
import MSCore
import NIOCore
import RootCore

/// Control a computer's screen from the panel. Every call needs the operator's login (writes also CSRF). A ticket belongs to the operator who opened it.
struct ScreenRoutes {
    let services: Services
    let guards: Guards

    static let opensPerMinute = 10
    static let inputPerMinute = 1_200
    static let framesPerMinute = 1_800

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/screen", use: status)
        group.post("/api/machines/{id}/screen", use: open)
        group.get("/api/screen/{ticket}/frame", use: frame)
        group.post("/api/screen/{ticket}/control", use: control)
        group.post("/api/screen/{ticket}/input", use: input)
        group.delete("/api/screen/{ticket}", use: close)
    }

    func status(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        let machine = try machineId(context)
        return try await answer { try Json.response(Status(try await services.screens.status(machine: machine))) }
    }

    func open(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("screen-open", per: context, max: Self.opensPerMinute, seconds: 60)
        let machine = try machineId(context)
        return try await answer {
            let session = try await services.screens.open(machine: machine, actor: caller.name)
            return try Json.response(Opened(session, idleSeconds: ScreenSessionBook.defaultIdleSeconds, maxSeconds: ScreenSessionBook.defaultMaxSeconds), status: .created)
        }
    }

    func frame(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorRead(request)
        try guards.limit("screen-frame", per: context, max: Self.framesPerMinute, seconds: 60)
        let ticket = try ticketId(context)
        return try await answer {
            let picture = try await services.screens.picture(ticket: ticket, actor: caller.name)
            var headers = HTTPFields()
            headers[.contentType] = picture.contentType
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: picture.data)))
        }
    }

    func control(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        let ticket = try ticketId(context)
        let body = try StrictObject(data: try await guards.body(request), allowed: ["confirm"])
        let confirmed = try body.bool("confirm")
        return try await answer { try Json.response(Opened(try services.screens.takeControl(ticket: ticket, actor: caller.name, confirmed: confirmed), idleSeconds: ScreenSessionBook.defaultIdleSeconds, maxSeconds: ScreenSessionBook.defaultMaxSeconds)) }
    }

    func input(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("screen-input", per: context, max: Self.inputPerMinute, seconds: 60)
        let ticket = try ticketId(context)
        guard let object = (try? JSONSerialization.jsonObject(with: try await guards.body(request))) as? [String: Any] else { throw ApiFailure.invalid("the input must be a JSON object") }
        return try await answer {
            try await services.screens.send(ticket: ticket, actor: caller.name, body: object)
            return Response(status: .noContent)
        }
    }

    func close(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try services.screens.close(ticket: try ticketId(context), actor: caller.name)
        return Response(status: .noContent)
    }

    // MARK: pieces

    private func answer(_ work: () async throws -> Response) async throws -> Response {
        do {
            return try await work()
        } catch ScreenFailure.machineNotFound {
            throw ApiFailure.notFound
        } catch ScreenFailure.unreachable {
            throw ApiFailure(status: .badGateway, code: "machine_unreachable", message: "that machine did not answer")
        } catch ScreenFailure.notReady(let reason) {
            throw ApiFailure(status: .conflict, code: "screen_not_ready", message: reason)
        } catch ScreenFailure.badInput(let reason) {
            throw ApiFailure.invalid(reason)
        } catch ScreenFailure.refused(let refusal) {
            throw Self.failure(refusal)
        } catch let refusal as ScreenRefusal {
            throw Self.failure(refusal)
        }
    }

    private static func failure(_ refusal: ScreenRefusal) -> ApiFailure {
        switch refusal {
        case .alreadyOpen: return ApiFailure(status: .conflict, code: "screen_in_use", message: "this screen is already open")
        case .noSuchSession: return .notFound
        case .ended(let reason): return ApiFailure(status: .gone, code: "screen_ended", message: reason)
        case .needsConfirm: return ApiFailure.invalid("control must be confirmed")
        case .viewOnly: return ApiFailure(status: .forbidden, code: "view_only", message: "this session is view only: switch control on first")
        }
    }

    private func machineId(_ context: RootContext) throws -> String {
        guard let id = context.parameters.get("id"), Ids.isValid(id) else { throw ApiFailure.notFound }
        return id
    }

    private func ticketId(_ context: RootContext) throws -> String {
        guard let ticket = context.parameters.get("ticket"), ScreenSessionBook.isValidTicket(ticket) else { throw ApiFailure.notFound }
        return ticket
    }
}

private struct Opened: Encodable {
    let ticket: String
    let machine: String
    let mode: String
    let idleSeconds: Int
    let maxSeconds: Int

    init(_ session: ScreenSession, idleSeconds: TimeInterval, maxSeconds: TimeInterval) {
        ticket = session.ticket
        machine = session.machine
        mode = session.mode.rawValue
        self.idleSeconds = Int(idleSeconds)
        self.maxSeconds = Int(maxSeconds)
    }
}

private struct Status: Encodable {
    let access: String
    let width: Int
    let height: Int
    let message: String?

    init(_ json: [String: Any]) {
        access = json["access"] as? String ?? "off"
        width = json["width"] as? Int ?? 0
        height = json["height"] as? Int ?? 0
        message = json["message"] as? String
    }
}
