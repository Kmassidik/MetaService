import Darwin
import Foundation
import MSCore

/// A private ssh-agent that only the Root uses. The parent's keys are stored sealed; this is where one is opened, in memory, so an ssh login
/// can use it without a key file in clear on the disk. The agent's socket is in a folder that only this user can enter.
final class SshAgentHost: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var directory: String?
    private var loaded: Set<String> = []

    static let agentProgram = "/usr/bin/ssh-agent"
    static let addProgram = "/usr/bin/ssh-add"

    var socket: String? { lock.withLock { directory.map { $0 + "/agent.sock" } } }

    /// Starts the agent the first time, and again if it has died. Returns the socket to give ssh as SSH_AUTH_SOCK.
    func ensureRunning() throws -> String {
        try lock.withLock {
            if let process, process.isRunning, let directory { return directory + "/agent.sock" }
            cleanup()
            let suffix = Tokens.random(bytes: 6).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(8)
            let folder = "/tmp/ms-ssh-\(getuid())-\(suffix)"
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let child = Process()
            child.executableURL = URL(fileURLWithPath: Self.agentProgram)
            child.arguments = ["-D", "-a", folder + "/agent.sock"]
            child.environment = SshProcess.baseEnvironment
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run()
            guard Self.waitForSocket(folder + "/agent.sock") else { child.terminate(); throw SshProcessFailure.missing }
            process = child
            directory = folder
            loaded = []
            return folder + "/agent.sock"
        }
    }

    /// Puts a private key (as text) into the agent, once. The key is passed on the standard input of ssh-add and is never written to a file.
    func add(privateKey: String, name: String) async throws {
        let socket = try ensureRunning()
        guard !lock.withLock({ loaded.contains(name) }) else { return }
        let result = try await SshProcess.run(Self.addProgram, ["-"], input: Data(privateKey.utf8), environment: ["SSH_AUTH_SOCK": socket], timeout: 10)
        guard result.status == 0 else { throw SshProcessFailure.missing }
        lock.withLock { _ = loaded.insert(name) }
    }

    func stop() {
        lock.withLock {
            process?.terminate()
            cleanup()
        }
    }

    private func cleanup() {
        process?.terminate()
        process = nil
        if let directory { try? FileManager.default.removeItem(atPath: directory) }
        directory = nil
        loaded = []
    }

    private static func waitForSocket(_ path: String) -> Bool {
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: path) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}
