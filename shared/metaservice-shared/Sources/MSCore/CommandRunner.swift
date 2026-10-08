import Foundation

public enum CommandFailure: Error {
    case missing
    case timedOut
    case tooMuchOutput
    case failed(Int32)
}

/// Runs one program with an argument list (never through a shell), with a time limit and an output limit.
public enum CommandRunner {
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval, maxOutput: Int = 4 * 1024 * 1024) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw CommandFailure.missing }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try runBlocking(executable, arguments, timeout: timeout, maxOutput: maxOutput) })
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], timeout: TimeInterval, maxOutput: Int) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let timer = DispatchSource.makeTimerSource()
        let timedOut = Flag()
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { timedOut.set(); process.terminate() }
        timer.resume()
        defer { timer.cancel() }
        var collected = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            collected.append(chunk)
            guard collected.count <= maxOutput else { process.terminate(); throw CommandFailure.tooMuchOutput }
        }
        process.waitUntilExit()
        guard !timedOut.isSet else { throw CommandFailure.timedOut }
        guard process.terminationStatus == 0 else { throw CommandFailure.failed(process.terminationStatus) }
        return collected
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }
}
