import Foundation
import AgentCore

/// Asks the system which interface holds the default route. Runs `/sbin/route` with a time limit and keeps a good answer for a minute, so a sample does not start a process every time.
final class DarwinDefaultRoute {
    static let routeTool = "/sbin/route"
    static let routeArguments = ["-n", "get", "default"]
    static let commandTimeoutSeconds: TimeInterval = 3
    static let cacheSeconds: TimeInterval = 60

    /// The last good answer and when it was learned.
    private struct Known {
        let name: String
        let learnedAt: Date
    }

    private var known: Known?

    /// The primary interface name, or nil when it is unknown right now. A failed lookup keeps the last good name for the cache window.
    func name(now: Date = Date()) -> String? {
        if let known, now.timeIntervalSince(known.learnedAt) < Self.cacheSeconds { return known.name }
        guard let name = Self.lookUp() else { return nil }
        known = Known(name: name, learnedAt: now)
        return name
    }

    /// Runs the route command without a shell. Nil on any failure: it cannot start, it runs past the time limit, it exits non-zero, or its output has no usable interface line.
    static func lookUp() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: routeTool)
        process.arguments = routeArguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        guard finished.wait(timeout: .now() + commandTimeoutSeconds) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return PrimaryInterface.parse(routeOutput: text)
    }
}
