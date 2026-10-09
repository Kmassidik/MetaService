import Darwin
import Foundation
import RootStore

/// Keeps the Agents that run on the control plane's own computer alive: starts them, starts them again if they stop, and starts them after the control plane restarts.
/// When the control plane is stopped on purpose, they stop with it.
final class LocalAgentSupervisor: @unchecked Sendable {
    private let store: LocalAgentStore
    private let lock = NSLock()
    private var processes: [String: Process] = [:]
    private var stopping = false
    private static let retryDelays: [Double] = [3, 10, 30, 60]

    init(store: LocalAgentStore) {
        self.store = store
    }

    func start(_ entry: LocalAgentEntry) throws {
        try store.save(entry)
        launch(entry, attempt: 0)
    }

    func resume() {
        for entry in (try? store.all()) ?? [] { launch(entry, attempt: 0) }
    }

    func stopAll() {
        let running = lock.withLock { () -> [Process] in
            stopping = true
            return Array(processes.values)
        }
        for process in running where process.isRunning { process.terminate() }
        for process in running { process.waitUntilExit() }
    }

    private func launch(_ entry: LocalAgentEntry, attempt: Int) {
        guard !lock.withLock({ stopping }) else { return }
        // Something already answers on the Agent's port (an Agent left from before): leave it alone rather than start a second one that cannot bind.
        guard !Self.isListening(port: entry.port) else { return }
        FileManager.default.createFile(atPath: entry.logPath, contents: nil, attributes: [.posixPermissions: 0o600])
        guard let log = FileHandle(forWritingAtPath: entry.logPath) else { return }
        log.seekToEndOfFile()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: entry.binary)
        process.arguments = entry.arguments
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            try? log.close()
            self?.stopped(entry, attempt: attempt)
        }
        do { try process.run() } catch { return stopped(entry, attempt: attempt) }
        lock.withLock { processes[entry.machine] = process }
    }

    private func stopped(_ entry: LocalAgentEntry, attempt: Int) {
        let again = lock.withLock { () -> Bool in
            processes[entry.machine] = nil
            return !stopping
        }
        guard again else { return }
        let delay = Self.retryDelays[min(attempt, Self.retryDelays.count - 1)]
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in self?.launch(entry, attempt: attempt + 1) }
    }

    static func isListening(port: Int) -> Bool {
        let socketId = socket(AF_INET, SOCK_STREAM, 0)
        guard socketId >= 0 else { return false }
        defer { close(socketId) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socketId, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
    }
}
