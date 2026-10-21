import Foundation
import Hummingbird
import HummingbirdWebSocket
import MSCore
import RootCore

/// The console: the panel asks for a ticket (a normal operator write), then opens the socket with it.
struct TerminalRoutes {
    let services: Services
    let guards: Guards

    static let ticketsPerMinute = 30

    func register(on group: RouterGroup<RootContext>) {
        group.post("/api/machines/{id}/workloads/{workload}/terminal", use: issue)
    }

    func registerSocket(on router: Router<TerminalContext>) {
        router.ws("/api/terminal/{ticket}", shouldUpgrade: { request, context in try self.check(request, context) }) { inbound, outbound, context in
            await self.serve(inbound, outbound, context)
        }
    }

    private func issue(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("terminal-ticket", per: context, max: Self.ticketsPerMinute, seconds: 60)
        guard let machine = context.parameters.get("id"), let workload = context.parameters.get("workload"), Ids.isValid(machine), Ids.isValid(workload) else { throw ApiFailure.notFound }
        let ticket = try services.terminal.issueTicket(operatorName: caller.name, key: ConsoleKey(machine: machine, workload: workload))
        return try Json.response(TicketReply(ticket: ticket, expiresIn: TerminalTickets.lifetimeSeconds))
    }

    /// Session, Host and Origin first, then the ticket. Nothing is upgraded until all of them pass.
    private func check(_ request: Request, _ context: TerminalContext) throws -> RouterShouldUpgrade {
        let caller = try guards.operatorRead(request)
        guard Origin.matches(header: request.headers[.origin], expected: services.config.publicBaseURL) else { throw ApiFailure.forbidden("request origin not allowed") }
        guard let ticket = context.parameters.get("ticket"), let key = services.terminal.redeem(ticket: ticket, operatorName: caller.name) else { throw ApiFailure.notFound }
        context.claim.set(.init(key: key, operatorName: caller.name))
        return .upgrade()
    }

    private func serve(_ inbound: WebSocketInboundStream, _ outbound: WebSocketOutboundWriter, _ context: WebSocketRouterContext<TerminalContext>) async {
        guard let claimed = context.requestContext.claim.get() else { return await TerminalBridge.close(outbound, .vmUnavailable) }
        await services.terminal.serve(claimed.key, operatorName: claimed.operatorName, inbound: inbound, outbound: outbound, logger: context.logger)
    }
}

private struct TicketReply: Encodable {
    let ticket: String
    let expiresIn: Int
}
