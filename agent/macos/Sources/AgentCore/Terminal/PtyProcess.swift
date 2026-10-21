import Foundation
import CPTY

public enum PtyError: Error, Equatable {
    case noPty
    case noProgram
    case notStarted
}

/// One program running in a real pty, so a person can type into it. The program is started from an argument list (no shell is added), and
/// `stop()` ends it and closes the pty. One PtyProcess is one console.
public final class PtyProcess: @unchecked Sendable {
    private static let readBytes = 16384
    private static let pollMillis: Int32 = 100

    private let lock = NSLock()
    /// Keystrokes are written here, in order, so a full pty buffer never blocks the reader or the caller.
    private let writeQueue = DispatchQueue(label: "metaservice.pty.write")
    private var master: Int32 = -1
    private var process: Process?
    private var stopped = false

    /// What the program prints; it ends when the program ends or `stop()` is called.
    public let output: AsyncStream<[UInt8]>
    private let outputSink: AsyncStream<[UInt8]>.Continuation

    public var processIdentifier: Int32 { lock.withLock { process?.processIdentifier ?? 0 } }

    /// Starts `command[0]` with the rest as its arguments.
    public init(command: [String], size: TerminalSize = .initial) throws {
        guard let program = command.first else { throw PtyError.noProgram }
        (output, outputSink) = AsyncStream<[UInt8]>.makeStream()
        var masterFd: Int32 = 0, slaveFd: Int32 = 0
        guard cpty_openpty(&masterFd, &slaveFd, UInt16(size.rows), UInt16(size.cols)) == 0 else { throw PtyError.noPty }
        let slave = FileHandle(fileDescriptor: slaveFd, closeOnDealloc: false)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: program)
        child.arguments = Array(command.dropFirst())
        child.standardInput = slave
        child.standardOutput = slave
        child.standardError = slave
        do { try child.run() } catch {
            close(masterFd); close(slaveFd)
            throw PtyError.notStarted
        }
        close(slaveFd)
        master = masterFd
        process = child
        startReading(masterFd)
    }

    /// Sends keystrokes to the program, in order. Ignored once stopped. A pty only takes so much at once (the shell echoes what it is sent), so the
    /// write happens on its own queue, in pieces, while the reader keeps draining the output.
    public func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        writeQueue.async { [self] in
            var sent = 0
            while sent < bytes.count {
                let fd = lock.withLock { master }
                guard fd >= 0 else { return }
                let count = bytes[sent...].withUnsafeBytes { Foundation.write(fd, $0.baseAddress, $0.count) }
                guard count > 0 else { return }
                sent += count
            }
        }
    }

    public func resize(_ size: TerminalSize) {
        lock.lock(); defer { lock.unlock() }
        guard master >= 0 else { return }
        _ = cpty_setsize(master, UInt16(size.rows), UInt16(size.cols))
    }

    /// Ends the program and closes the pty. The reader notices within a fraction of a second, kills what is left and closes `output`.
    public func stop() {
        let child: Process? = lock.withLock {
            stopped = true
            return process
        }
        guard let child, child.isRunning else { return }
        kill(child.processIdentifier, SIGHUP)
    }

    private func startReading(_ fd: Int32) {
        Thread.detachNewThread { [self] in
            readLoop(fd)
            closeMaster()
            outputSink.finish()
        }
    }

    private func readLoop(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: Self.readBytes)
        while !lock.withLock({ stopped }) {
            var watch = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&watch, 1, Self.pollMillis)
            guard ready >= 0 else { return }
            guard ready > 0 else { continue }
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { return }
            outputSink.yield(Array(buffer[0..<count]))
        }
    }

    /// Closes the pty and makes sure the program is gone (an interactive shell may shrug off a hangup).
    private func closeMaster() {
        lock.lock(); defer { lock.unlock() }
        if let child = process, child.isRunning { kill(child.processIdentifier, SIGKILL) }
        guard master >= 0 else { return }
        let fd = master
        master = -1
        writeQueue.async { close(fd) }
    }
}
