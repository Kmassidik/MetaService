import Darwin
import Foundation
import AgentCore
import MSCore

/// The real Mac behind the security route: the files and the commands, all as the helper's own user (no root, no sudo).
enum SecurityHost {
    static let commandTimeout: TimeInterval = 10

    static func makeService(homeDirectory: String = NSHomeDirectory()) -> SecurityService {
        let files = DiskFiles()
        let run: BaselineChecks.Run = { try await CommandRunner.run($0, $1, timeout: commandTimeout) }
        let pending = PendingUpdates { try await CommandRunner.run($0, $1, timeout: $2) }
        return SecurityService(sshdConfig: SshdConfigResolver(files: files), files: files, homeDirectory: homeDirectory, run: run, pending: pending)
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
