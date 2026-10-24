import Foundation

/// When a sandbox ends, kept pure so create, the timeout route and the helper events all agree.
public enum SandboxEndTime {
    /// A sandbox runs 5 minutes unless the program asks for another time (see sandbox/README.md).
    public static let defaultTimeoutSeconds = 300
    /// Nothing lives longer than a day in v1, however often its timeout is moved.
    public static let maximumLifeSeconds = 86_400
    public static let minimumTimeoutSeconds = 1

    public enum RefusalReason: String, Equatable {
        case timeoutTooShort = "timeout_too_short"
        case timeoutTooLong = "timeout_too_long"
    }

    /// A timeout that cannot be granted, with the longest one that can at that moment.
    public struct Refusal: Error, Equatable {
        public let reason: RefusalReason
        public let message: String
        public let maximumSeconds: Int

        public init(reason: RefusalReason, message: String, maximumSeconds: Int) {
            self.reason = reason
            self.message = message
            self.maximumSeconds = maximumSeconds
        }
    }

    /// The end time a create or a timeout change asks for. It may be moved again later, but never past `createdAt` plus
    /// the team's longest life, so a program cannot keep one sandbox alive forever.
    public static func end(createdAt: Date, now: Date, timeoutSeconds: Int,
                           maxLifeSeconds: Int = maximumLifeSeconds) throws -> Date {
        let longest = longestTimeout(createdAt: createdAt, now: now, maxLifeSeconds: maxLifeSeconds)
        guard timeoutSeconds >= minimumTimeoutSeconds else {
            throw Refusal(reason: .timeoutTooShort, message: "A sandbox must run at least \(minimumTimeoutSeconds) second.",
                          maximumSeconds: longest)
        }
        guard timeoutSeconds <= longest else {
            throw Refusal(reason: .timeoutTooLong, message: "A sandbox may run at most \(longest) more seconds on this team.",
                          maximumSeconds: longest)
        }
        return now.addingTimeInterval(TimeInterval(timeoutSeconds))
    }

    /// The longest timeout a sandbox made at `createdAt` may still be given now.
    public static func longestTimeout(createdAt: Date, now: Date, maxLifeSeconds: Int = maximumLifeSeconds) -> Int {
        Int(max(0, createdAt.addingTimeInterval(TimeInterval(maxLifeSeconds)).timeIntervalSince(now)).rounded(.down))
    }

    /// How long is left before the end time, never negative. What the panel shows and what a create answers.
    public static func remainingSeconds(until endAt: Date, now: Date) -> Int {
        Int(max(0, endAt.timeIntervalSince(now)).rounded(.down))
    }
}
