import Foundation
import HTTPTypes
import HummingbirdWebSocket
import Logging
import MSCore
import NIOCore
import NIOWebSocket
import RootCore
import WSClient

/// Pipes frames between the browser and the machine's helper without reading what is in them. It looks at sizes, applies the limits, and ends the console when it must.
struct TerminalBridge: Sendable {
    let sessions: TerminalSessions
    let clock: Clock
    let client: AgentClient
    let tunnels: TunnelPorts

    /// What the socket library accepts. It is twice the rule, so the rule (and its close code 1008) is what a too-big frame meets first.
    static let socketFrameBytes = 2 * TerminalFrames.maxInputBytes
    static let helperOutputBytes = 1 << 20
    private static let watchSeconds: UInt64 = 1

    /// Opens the helper socket and runs the console until it ends, then closes the browser's socket with the reason.
    func run(_ key: ConsoleKey, inbound: WebSocketInboundStream, outbound: WebSocketOutboundWriter, logger: Logger) async -> CloseReason {
        let ended = EndedBy()
        do {
            let (url, token) = try client.target(machine: key.machine, scheme: "ws", path: "/v1/workloads/\(key.workload)/terminal")
            var headers = HTTPFields()
            headers[.authorization] = "Bearer \(token)"
            let configuration = WebSocketClientConfiguration(maxFrameSize: Self.helperOutputBytes, additionalHeaders: headers)
            try await WebSocketClient.connect(url: url.absoluteString, configuration: configuration, logger: logger) { helperIn, helperOut, _ in
                await ended.set(await pipe(key, browserIn: inbound, browserOut: outbound, helperIn: helperIn, helperOut: helperOut))
            }
        } catch let error as WebSocketClientError where error == .init(.webSocketUpgradeFailed) {
            await ended.set(.vmUnavailable)
        } catch {
            await ended.set(.machineOffline)
        }
        let reason = await ended.value ?? .machineOffline
        await Self.close(outbound, reason)
        return reason
    }

    static func close(_ outbound: WebSocketOutboundWriter, _ reason: CloseReason) async {
        try? await outbound.close(.unknown(reason.code), reason: reason.text)
    }

    // MARK: the pipe

    /// Runs the two pumps and the watch until the first one says the console is over, then closes both sockets so the others stop.
    private func pipe(_ key: ConsoleKey, browserIn: WebSocketInboundStream, browserOut: WebSocketOutboundWriter,
                      helperIn: WebSocketInboundStream, helperOut: WebSocketOutboundWriter) async -> CloseReason {
        await withTaskGroup(of: CloseReason.self) { group in
            group.addTask { await fromBrowser(key, browserIn, to: helperOut) }
            group.addTask { await fromHelper(key, helperIn, to: browserOut) }
            group.addTask { await watch(key) }
            let reason = await group.next() ?? .machineOffline
            await Self.close(browserOut, reason)
            try? await helperOut.close(.normalClosure, reason: nil)
            group.cancelAll()
            return reason
        }
    }

    private func fromBrowser(_ key: ConsoleKey, _ stream: WebSocketInboundStream, to helper: WebSocketOutboundWriter) async -> CloseReason {
        do {
            for try await message in stream.messages(maxSize: Self.socketFrameBytes) {
                if let refusal = refusal(of: message) { return refusal }
                sessions.touch(key, now: clock.now)
                try await helper.write(message.outbound)
            }
            return .browserLeft
        } catch {
            return .badFrame
        }
    }

    private func refusal(of message: WebSocketMessage) -> CloseReason? {
        switch message {
        case .binary(let buffer): return TerminalFrames.checkInput(byteCount: buffer.readableBytes)
        case .text(let text): return TerminalFrames.checkResize(text: text)
        }
    }

    private func fromHelper(_ key: ConsoleKey, _ stream: WebSocketInboundStream, to browser: WebSocketOutboundWriter) async -> CloseReason {
        do {
            for try await message in stream.messages(maxSize: Self.helperOutputBytes) {
                guard case .binary(let output) = message else { continue }
                sessions.touch(key, now: clock.now)
                try await browser.write(.binary(output))
            }
        } catch {
            return .machineOffline
        }
        return tunnelIsDown(key.machine) ? .machineOffline : .shellEnded
    }

    /// A helper that went quiet because its tunnel fell is "offline", not "the shell ended".
    private func tunnelIsDown(_ machine: String) -> Bool {
        guard case .some(.none) = tunnels.route(for: machine) else { return false }
        return true
    }

    private func watch(_ key: ConsoleKey) async -> CloseReason {
        while !Task.isCancelled {
            if let reason = sessions.endReason(key, now: clock.now) { return reason }
            try? await Task.sleep(nanoseconds: Self.watchSeconds * 1_000_000_000)
        }
        return .browserLeft
    }
}

private extension WebSocketMessage {
    var outbound: WebSocketOutboundWriter.OutboundFrame {
        switch self {
        case .binary(let buffer): return .binary(buffer)
        case .text(let text): return .text(text)
        }
    }
}

/// Holds the reason the pipe gave, so it can be read after the helper socket's closure returns.
private actor EndedBy {
    private(set) var value: CloseReason?
    func set(_ reason: CloseReason) { if value == nil { value = reason } }
}
