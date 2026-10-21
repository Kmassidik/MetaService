import Foundation
import HummingbirdWebSocket
import Logging
import MSCore
import RootCore
import RootStore

/// The console's books and what they need from the rest of the Root: who may open one, the audit trail, and ending consoles when their VM or machine goes.
final class TerminalService: @unchecked Sendable {
    private let machines: MachineStore
    private let audit: AuditStore
    private let clock: Clock
    private let bridge: TerminalBridge
    private let tickets = TerminalTickets()
    private let sessions: TerminalSessions

    init(machines: MachineStore, audit: AuditStore, clock: Clock, client: AgentClient, tunnels: TunnelPorts) {
        let sessions = TerminalSessions()
        self.sessions = sessions
        self.machines = machines
        self.audit = audit
        self.clock = clock
        bridge = TerminalBridge(sessions: sessions, clock: clock, client: client, tunnels: tunnels)
    }

    // MARK: tickets

    /// A ticket for a running VM that has no console yet. Holds the console's place until the ticket is used or runs out.
    func issueTicket(operatorName: String, key: ConsoleKey) throws -> String {
        try requireRunning(key)
        do {
            try sessions.reserve(key, now: clock.now)
        } catch ConsoleRefusal.alreadyOpen {
            throw ApiFailure(status: .conflict, code: "console_open", message: "this VM already has a console open")
        } catch {
            throw ApiFailure(status: .tooManyRequests, code: "too_many_consoles", message: "\(TerminalSessions.total) consoles are open already: close one first")
        }
        let ticket = Tokens.random()
        tickets.issue(token: ticket, operatorName: operatorName, key: key, now: clock.now)
        return ticket
    }

    func redeem(ticket: String, operatorName: String) -> ConsoleKey? {
        tickets.redeem(token: ticket, operatorName: operatorName, now: clock.now)
    }

    private func requireRunning(_ key: ConsoleKey) throws {
        let machine: MachineSummary
        do {
            machine = try machines.get(id: key.machine, now: clock.now)
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
        guard let vm = machine.workloads.first(where: { $0.id == key.workload }) else { throw ApiFailure.notFound }
        guard TerminalSupport.isSupported(machineOS: machine.os ?? "") else { throw ApiFailure(status: .conflict, code: "not_supported", message: TerminalSupport.message) }
        guard machine.state != "offline" else { throw ApiFailure(status: .badGateway, code: "unreachable", message: "the machine is offline") }
        guard vm.state == "running" else { throw ApiFailure(status: .conflict, code: "not_running", message: "the VM is not running") }
    }

    // MARK: the open console

    /// Runs one console until it ends. The audit lines say who, where and for how long, and never what was typed or shown.
    func serve(_ key: ConsoleKey, operatorName: String, inbound: WebSocketInboundStream, outbound: WebSocketOutboundWriter, logger: Logger) async {
        guard sessions.open(key, now: clock.now) else { return await TerminalBridge.close(outbound, .vmUnavailable) }
        record("console_open", operatorName, key, seconds: nil)
        let reason = await bridge.run(key, inbound: inbound, outbound: outbound, logger: logger)
        record("console_close", operatorName, key, seconds: sessions.close(key, now: clock.now), reason: reason.text)
    }

    private func record(_ action: String, _ operatorName: String, _ key: ConsoleKey, seconds: Int?, reason: String? = nil) {
        var detail = ["vm": key.workload]
        if let seconds { detail["seconds"] = String(seconds) }
        if let reason { detail["reason"] = reason }
        try? audit.record(actor: operatorName, action: action, target: key.machine, detail: detail, at: clock.now)
    }

    // MARK: ending consoles from the outside

    /// The VM was stopped or deleted from the panel.
    func vmActed(machine: String, workload: String, action: WorkloadService.Action) {
        guard action != .start else { return }
        sessions.requestEnd(ConsoleKey(machine: machine, workload: workload), action == .stop ? .vmStopped : .vmDeleted)
    }

    func machineRemoved(_ machine: String) {
        sessions.requestEnd(machine: machine, .machineRemoved)
    }
}
