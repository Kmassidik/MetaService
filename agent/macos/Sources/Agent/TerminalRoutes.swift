import Foundation
import Hummingbird
import HummingbirdWebSocket
import HTTPTypes
import NIOCore
import NIOWebSocket
import WSCore
import AgentCore
import MSCore

/// `GET /v1/workloads/{id}/terminal`: a WebSocket that carries one interactive shell inside a running workload. docs/console-contract.md.
///
/// The WebSocket library answers every refused upgrade with a bare 400, so the exact reasons come from the same GET sent WITHOUT an Upgrade header:
/// the checks live in `check` and run on both routers. On the WebSocket router a failure means "do not upgrade"; on the plain router it is the
/// answer (401, 404, 409 with the usual error JSON), and a request that passes gets 426.
struct TerminalRoutes {
    let service: AgentService
    let consoles: ConsoleRegistry
    let token: String

    static let upgradeRequired = HTTPResponse.Status(code: 426, reasonPhrase: "Upgrade Required")
    private static let path: RouterPath = "/v1/workloads/{id}/terminal"
    /// A little above the 64 KiB input cap, so an oversize frame reaches our own rule and is closed with 1008 rather than the library's 1009.
    static let socketFrameBytes = TerminalFrames.maxInputBytes * 2

    func registerPlain(on router: Router<AgentContext>) {
        router.get(Self.path) { _, context -> Response in
            _ = try await check(id: Self.workloadId(context.parameters))
            throw ApiFailure(status: Self.upgradeRequired, code: "upgrade_required", message: "this address only speaks WebSocket")
        }
    }

    func socketRouter() -> Router<BasicWebSocketRequestContext> {
        let router = Router(context: BasicWebSocketRequestContext.self)
        router.ws(Self.path, shouldUpgrade: { request, context in
            try authorize(request)
            _ = try await check(id: Self.workloadId(context.parameters))
            return .upgrade([:])
        }, onUpgrade: { inbound, outbound, context in
            try await serve(id: try Self.workloadId(context.requestContext.parameters), inbound, outbound)
        })
        return router
    }

    // MARK: checks

    private func authorize(_ request: Request) throws {
        guard let sent = TokenMiddleware.bearer(request), Tokens.constantTimeEqual(sent, token) else { throw ApiFailure.unauthorized }
    }

    private func check(id: String) async throws -> Workload {
        guard let workload = try await service.workloads().first(where: { $0.id == id }) else { throw ApiFailure.notFound }
        guard workload.state == .running else { throw ApiFailure(status: .conflict, code: "not_running", message: "the VM is not running") }
        guard !consoles.isOpen(id) else { throw ApiFailure(status: .conflict, code: "console_open", message: "this VM already has a console") }
        return workload
    }

    private static func workloadId(_ parameters: Parameters) throws -> String {
        guard let id = parameters.get("id"), Ids.isValid(id) else { throw ApiFailure.notFound }
        return id
    }

    // MARK: the console

    private func serve(id: String, _ inbound: WebSocketInboundStream, _ outbound: WebSocketOutboundWriter) async throws {
        let (ends, endSink) = AsyncStream<ConsoleClose>.makeStream()
        guard consoles.claim(id, onEnd: { endSink.yield($0) }) else { return try await close(outbound, .alreadyOpen) }
        defer { consoles.release(id); endSink.finish() }
        guard let pty = await start(id: id) else { return try await close(outbound, .couldNotStart) }
        defer { pty.stop() }
        let ending = try await withThrowingTaskGroup(of: ConsoleClose?.self) { group in
            group.addTask { try await Self.pumpOutput(pty, outbound) }
            group.addTask { try await Self.pumpInput(inbound, pty) }
            group.addTask { await ends.first { _ in true } }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let ending { try await close(outbound, ending) }
    }

    private func start(id: String) async -> PtyProcess? {
        guard let command = try? await service.attach(id: id) else { return nil }
        return try? PtyProcess(command: command)
    }

    /// Shell output to the browser. When the shell ends, the console ends with it.
    private static func pumpOutput(_ pty: PtyProcess, _ outbound: WebSocketOutboundWriter) async throws -> ConsoleClose? {
        for await chunk in pty.output { try await outbound.write(.binary(ByteBuffer(bytes: chunk))) }
        return .shellEnded
    }

    /// Browser messages to the shell. Ends with nil when the browser leaves, or with the reason when it breaks the rules.
    private static func pumpInput(_ inbound: WebSocketInboundStream, _ pty: PtyProcess) async throws -> ConsoleClose? {
        for try await message in inbound.messages(maxSize: socketFrameBytes) {
            switch message.consoleInput {
            case .keys(let bytes): pty.write(bytes)
            case .resize(let size): pty.resize(size)
            case .refused: return .badFrame
            }
        }
        return nil
    }

    private func close(_ outbound: WebSocketOutboundWriter, _ ending: ConsoleClose) async throws {
        try await outbound.close(WebSocketErrorCode(codeNumber: Int(ending.code)), reason: ending.reason)
    }
}

private extension WebSocketMessage {
    var consoleInput: ConsoleInput {
        switch self {
        case .binary(let buffer): TerminalFrames.input(binary: Array(buffer.readableBytesView))
        case .text(let text): TerminalFrames.input(text: text)
        }
    }
}
