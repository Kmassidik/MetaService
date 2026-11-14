import Darwin
import Foundation

/// Opening a macOS privacy-protected folder (a Photos library, Mail, Messages) can block forever while the system waits for a
/// permission prompt nobody sees. The open runs on a side thread; after the limit the folder is skipped, and a late descriptor is closed.
enum DarwinGuardedOpen {
    static let limit: TimeInterval = 3
    static let guardedPrefix = "/Users/"
    static let guardedDepth = 6

    static func shouldGuard(path: String, depth: Int) -> Bool { depth <= guardedDepth && path.hasPrefix(guardedPrefix) }

    static func directory(_ path: String, guarded: Bool, limit: TimeInterval = limit,
                          opener: @escaping @Sendable (String) -> Int32 = { Darwin.open($0, O_RDONLY | O_DIRECTORY) }) -> Int32 {
        guard guarded else { return opener(path) }
        let gate = Gate()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            let descriptor = opener(path)
            if !gate.finish(descriptor) && descriptor >= 0 { Darwin.close(descriptor) }
            done.signal()
        }
        guard done.wait(timeout: .now() + limit) == .success else {
            gate.abandon()
            return -1
        }
        return gate.descriptor
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var abandoned = false
        private(set) var descriptor: Int32 = -1

        /// True when the caller still wants the descriptor.
        func finish(_ value: Int32) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !abandoned else { return false }
            descriptor = value
            return true
        }

        func abandon() {
            lock.lock()
            abandoned = true
            lock.unlock()
        }
    }
}
