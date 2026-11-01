import Darwin
import Foundation
import AgentCore
import MSCore

/// The files of `autostart` as the helper's own user sees them.
struct AutostartDiskFiles: AutostartFiles {
    func read(_ path: String) -> Data? { FileManager.default.contents(atPath: path) }

    func write(_ data: Data, to path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func remove(_ path: String) throws { try FileManager.default.removeItem(atPath: path) }

    func processAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
}

/// `metaservice-agent autostart on|off|status [--box DIR]`. The box is the folder above the folder this program sits in (`<box>/bin/metaservice-agent`).
enum AutostartCommand {
    static let verb = "autostart"
    static let usage = "usage: metaservice-agent autostart on|off|status [--box DIR]"
    static let boxOption = "--box"
    static let commandTimeout: TimeInterval = 20

    /// Runs the verb and returns the exit code; a failure is told on standard error like the other verbs.
    static func run(_ arguments: [String]) async -> Int32 {
        do {
            let (action, box) = try parse(arguments)
            let service = AutostartService(files: AutostartDiskFiles(), run: { try await CommandRunner.run($0, $1, timeout: commandTimeout) }, home: NSHomeDirectory(), box: box, uid: getuid())
            let outcome = try await service.perform(action)
            outcome.lines.forEach { print($0) }
            return outcome.code
        } catch {
            FileHandle.standardError.write(Data("metaservice-agent: \(error)\n".utf8))
            return 1
        }
    }

    static func parse(_ arguments: [String]) throws -> (AutostartService.Action, String) {
        guard let word = arguments.first, let action = AutostartService.Action(rawValue: word) else { throw ConfigError(description: usage) }
        switch arguments.count {
        case 1: return (action, try boxOfThisProgram())
        case 3 where arguments[1] == boxOption: return (action, arguments[2])
        default: throw ConfigError(description: usage)
        }
    }

    private static func boxOfThisProgram() throws -> String {
        guard let program = Bundle.main.executableURL?.resolvingSymlinksInPath() else { throw ConfigError(description: "cannot find this program") }
        return program.deletingLastPathComponent().deletingLastPathComponent().path
    }
}
