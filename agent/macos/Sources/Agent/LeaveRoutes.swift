import Foundation
import Hummingbird
import AgentCore

/// "Clean the computer too": the admin removed this computer in the panel and typed its sudo password. The password is the first line of the clean-up script's standard input,
/// used once and never logged or kept. The script does the root step first and prints one marker line; only after `root-ok` does it delete anything, so a wrong password changes nothing.
struct LeaveRoutes {
    static let longestPassword = 256
    static let rootStepSeconds = 60.0
    static let marker = "ms-leave: "

    enum Outcome: Equatable {
        case leaving, notJoined
        case failed(String)
    }

    /// The join folder is the parent of the helper's state folder (`~/.metaservice-join/state`).
    let stateDirectory: String

    func register(on router: Router<AgentContext>) {
        router.post("/v1/leave") { request, _ in
            let body = try await AgentRoutes.body(request)
            let password = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["sudo_password"] as? String ?? ""
            guard password.utf8.count <= Self.longestPassword, !password.contains("\n") else { return Json.error(.badRequest, "invalid_input", "the password is not acceptable") }
            switch await Self.run(stateDirectory: stateDirectory, password: password, sudo: nil) {
            case .leaving: return try Json.response(["leaving": true])
            case .notJoined: return Json.error(.notFound, "not_joined", "this computer did not join through the join script, so there is nothing to clean")
            case .failed(let why): return Json.error(.conflict, "leave_failed", why)
            }
        }
    }

    static func read(marker line: String) -> Outcome? {
        guard line.hasPrefix(marker) else { return nil }
        let said = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        switch said {
        case "root-ok": return .leaving
        case "not-joined", "unreadable": return .notJoined
        default:
            let reason = said.hasPrefix("root-failed: ") ? String(said.dropFirst("root-failed: ".count)) : said
            return .failed(String(reason.prefix(200)))
        }
    }

    /// `sudo` is only changed by tests.
    static func run(stateDirectory: String, password: String, sudo: String?) async -> Outcome {
        let home = (stateDirectory as NSString).deletingLastPathComponent
        guard FileManager.default.fileExists(atPath: home + "/joined.env") else { return .notJoined }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", LeaveScript.text, "leave", home]
        if let sudo { process.environment = ProcessInfo.processInfo.environment.merging(["MS_LEAVE_SUDO": sudo]) { $1 } }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failed("the clean-up could not be started") }
        input.fileHandleForWriting.write(Data((password + "\n").utf8))
        try? input.fileHandleForWriting.close()
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let deadline = Date().addingTimeInterval(rootStepSeconds)
                var pending = Data()
                var answer: Outcome?
                while answer == nil, Date() < deadline {
                    let chunk = output.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    pending.append(chunk)
                    for line in String(decoding: pending, as: UTF8.self).split(separator: "\n") {
                        if let found = read(marker: String(line)) { answer = found; break }
                    }
                }
                continuation.resume(returning: answer ?? .failed("the clean-up ended without an answer"))
            }
        }
    }
}
