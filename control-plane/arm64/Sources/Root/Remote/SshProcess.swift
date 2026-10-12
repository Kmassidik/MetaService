import Foundation

struct SshResult {
    let status: Int32
    let output: String
    let errors: String
}

enum SshProcessFailure: Error {
    case missing, timedOut, tooMuchOutput
}

/// Runs one of the ssh programs (ssh, ssh-keyscan, ssh-keygen, ssh-add) with an argument list, never through a shell. The program gets a small, fixed
/// environment: not the Root's own, so no ssh agent, key or setting of the operator's can leak in. Whatever is given as `input` is written to its standard input.
enum SshProcess {
    static let baseEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"]
    private static let defaultOutputLimit = 1_048_576

    static func run(_ executable: String, _ arguments: [String], input: Data? = nil, environment extra: [String: String] = [:], timeout: TimeInterval,
                    maxOutput: Int = defaultOutputLimit) async throws -> SshResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw SshProcessFailure.missing }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try runBlocking(executable, arguments, input: input, environment: baseEnvironment.merging(extra) { $1 }, timeout: timeout, maxOutput: maxOutput) })
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], input: Data?, environment: [String: String], timeout: TimeInterval, maxOutput: Int) throws -> SshResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let output = Pipe(), errors = Pipe(), stdin = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        let collector = Collector(limit: maxOutput)
        errors.fileHandleForReading.readabilityHandler = { collector.addError($0.availableData) }
        try process.run()
        if let input {
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
        }
        let timedOut = Flag()
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { timedOut.set(); process.terminate() }
        timer.resume()
        defer { timer.cancel() }
        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            guard collector.addOutput(chunk) else { process.terminate(); throw SshProcessFailure.tooMuchOutput }
        }
        process.waitUntilExit()
        errors.fileHandleForReading.readabilityHandler = nil
        guard !timedOut.isSet else { throw SshProcessFailure.timedOut }
        return SshResult(status: process.terminationStatus, output: collector.output, errors: collector.errors)
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var out = Data()
        private var err = Data()
        init(limit: Int) { self.limit = limit }
        func addOutput(_ data: Data) -> Bool { lock.withLock { out.append(data); return out.count <= limit } }
        func addError(_ data: Data) { lock.withLock { err.append(data); if err.count > 8192 { err = err.suffix(8192) } } }
        var output: String { lock.withLock { String(decoding: out, as: UTF8.self) } }
        var errors: String { lock.withLock { String(decoding: err, as: UTF8.self) } }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }
}
