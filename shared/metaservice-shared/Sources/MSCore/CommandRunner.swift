import Foundation

public enum CommandFailure: Error {
    case missing
    case timedOut
    case tooMuchOutput
    case failed(Int32, String)
}

/// Runs one program with an argument list (never through a shell), with a time limit and an output limit. `input`, when given, is sent on standard input.
public enum CommandRunner {
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval, maxOutput: Int = 4 * 1024 * 1024, input: Data? = nil) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw CommandFailure.missing }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try runBlocking(executable, arguments, timeout: timeout, maxOutput: maxOutput, input: input) })
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], timeout: TimeInterval, maxOutput: Int, input: Data?) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        let errors = Pipe()
        let tail = Tail(limit: 4096)
        errors.fileHandleForReading.readabilityHandler = { handle in tail.append(handle.availableData) }
        process.standardError = errors
        let standardInput = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : standardInput
        try process.run()
        if let input { feed(input, to: standardInput) }
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
        errors.fileHandleForReading.readabilityHandler = nil
        guard !timedOut.isSet else { throw CommandFailure.timedOut }
        guard process.terminationStatus == 0 else { throw CommandFailure.failed(process.terminationStatus, tail.text) }
        return collected
    }

    /// Sends the bytes to the program's standard input from another thread (so a program that prints before it reads cannot block us), then closes it.
    /// The bytes are data for the program to read; they are never part of the argument list.
    private static func feed(_ input: Data, to pipe: Pipe) {
        signal(SIGPIPE, SIG_IGN)
        DispatchQueue.global().async {
            // A program that quits before reading everything makes these fail; its exit status and error text already say so.
            try? pipe.fileHandleForWriting.write(contentsOf: input)
            try? pipe.fileHandleForWriting.close()
        }
    }

    /// Keeps the last few KB of what a program wrote to stderr, to say why it failed.
    private final class Tail: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private let limit: Int
        init(limit: Int) { self.limit = limit }
        func append(_ more: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(more)
            if data.count > limit { data = data.suffix(limit) }
        }
        var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }
}
