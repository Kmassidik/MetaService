import Darwin
import Foundation
import AgentCore
import MSCore

/// The real Mac behind the security route: the files, the `log` tool and the commands, all as the helper's own user (no root, no sudo).
enum SecurityHost {
    static let logTool = "/usr/bin/log"
    static let logPredicate = "process == \"\(SshConnectionLog.processName)\""
    /// The log of a busy machine is big; this is far above six hours of one process.
    static let maxLogBytes = 64 * 1024 * 1024
    static let commandTimeout: TimeInterval = 10
    private static let logTimeFormat = "yyyy-MM-dd HH:mm:ss"

    static func makeService(homeDirectory: String = NSHomeDirectory(), budget: TimeInterval = SecurityEventsReader.budgetSeconds, history: Int = SecurityEventsReader.historySeconds) -> SecurityService {
        let files = DiskFiles()
        let run: BaselineChecks.Run = { try await CommandRunner.run($0, $1, timeout: commandTimeout) }
        let reader = SecurityEventsReader(budget: budget, history: history, readLog: readLog)
        let pending = PendingUpdates { try await CommandRunner.run($0, $1, timeout: $2) }
        return SecurityService(reader: reader, sshdConfig: SshdConfigResolver(files: files), files: files, homeDirectory: homeDirectory, run: run, pending: pending)
    }

    /// The `sshd-session` lines of one window of the log, as compact text. The times are given in the machine's own zone, as `log show` reads them.
    @Sendable static func readLog(start: Int, end: Int, timeout: TimeInterval) async throws -> String {
        let data = try await CommandRunner.run(logTool, ["show", "--style", "compact", "--predicate", logPredicate, "--start", logTime(start), "--end", logTime(end)],
                                               timeout: timeout, maxOutput: maxLogBytes)
        return String(decoding: data, as: UTF8.self)
    }

    private static func logTime(_ epoch: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = logTimeFormat
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}

/// Files as the helper's user sees them.
struct DiskFiles: SshdConfigFiles, MacFiles {
    func read(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }
    func read(_ path: String) -> Data? { FileManager.default.contents(atPath: path) }
    func list(_ directory: String) -> [String]? { try? FileManager.default.contentsOfDirectory(atPath: directory).sorted() }

    func expand(_ pattern: String) -> [String] {
        var found = glob_t()
        defer { globfree(&found) }
        guard glob(pattern, 0, nil, &found) == 0 else { return [] }
        return (0..<Int(found.gl_pathc)).compactMap { found.gl_pathv[$0].map { String(cString: $0) } }
    }
}
