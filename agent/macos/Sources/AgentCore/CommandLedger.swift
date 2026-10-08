import Foundation

/// Remembers every command by its id, so a repeat never runs twice. Old entries are dropped once the ledger is full.
/// With a `persist` function it also survives a restart: whatever was still running then is marked failed, because its work died with the Agent.
public final class CommandLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [String: Command] = [:]
    private var order: [String] = []
    private let capacity: Int
    private let persist: (([Command]) -> Void)?

    public init(capacity: Int = 2000, restored: [Command] = [], persist: (([Command]) -> Void)? = nil) {
        self.capacity = capacity
        self.persist = persist
        for var command in restored.suffix(capacity) {
            if command.state == .running || command.state == .queued {
                command.state = .failed
                command.result = ["error": "the Agent restarted before this finished"]
            }
            commands[command.commandId] = command
            order.append(command.commandId)
        }
    }

    public func find(_ id: String) -> Command? {
        lock.lock(); defer { lock.unlock() }
        return commands[id]
    }

    public func record(_ command: Command) {
        lock.lock()
        if commands[command.commandId] == nil { order.append(command.commandId) }
        commands[command.commandId] = command
        while order.count > capacity { commands[order.removeFirst()] = nil }
        let snapshot = order.compactMap { commands[$0] }
        lock.unlock()
        persist?(snapshot)
    }
}
