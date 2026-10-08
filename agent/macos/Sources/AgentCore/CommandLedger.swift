import Foundation

/// Remembers every command by its id, so a repeat never runs twice. Old entries are dropped once the ledger is full.
public final class CommandLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [String: Command] = [:]
    private var order: [String] = []
    private let capacity: Int

    public init(capacity: Int = 2000) { self.capacity = capacity }

    public func find(_ id: String) -> Command? {
        lock.lock(); defer { lock.unlock() }
        return commands[id]
    }

    public func record(_ command: Command) {
        lock.lock(); defer { lock.unlock() }
        if commands[command.commandId] == nil { order.append(command.commandId) }
        commands[command.commandId] = command
        while order.count > capacity { commands[order.removeFirst()] = nil }
    }
}
