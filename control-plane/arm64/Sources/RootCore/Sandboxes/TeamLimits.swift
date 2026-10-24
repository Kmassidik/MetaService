import Foundation

/// The sizes a sandbox is asked for, and what a team may have. Pure: the numbers come in, the answer goes out.
public struct SandboxShape: Equatable, Sendable {
    /// What `base` gives when the template and the team say nothing else (see sandbox/README.md).
    public static let defaultVcpu = 2
    public static let defaultRamMb = 512
    public static let defaultDiskMb = 10 * 1024

    public let vcpu: Int
    public let ramMb: Int
    public let diskMb: Int

    public init(vcpu: Int = defaultVcpu, ramMb: Int = defaultRamMb, diskMb: Int = defaultDiskMb) {
        self.vcpu = vcpu
        self.ramMb = ramMb
        self.diskMb = diskMb
    }
}

/// What a team may use. A team with no limits of its own gets `standard`, which is one of our own apps' share of a
/// sandbox machine, not a public plan.
public struct TeamLimits: Equatable, Codable, Sendable {
    /// How many sandboxes may run at once. Paused ones do not count, since they use no CPU or memory.
    public static let defaultMaxRunning = 10
    /// The most vCPU the team's running sandboxes may hold together.
    public static let defaultMaxVcpu = 8
    /// The most memory the team's running sandboxes may hold together, in MB.
    public static let defaultMaxRamMb = 8 * 1024
    /// How many sandboxes may be made in one hour, however short-lived, so a broken program cannot spin forever.
    public static let defaultMaxSandboxesPerHour = 60
    /// The window the per-hour count looks back over.
    public static let hourlyWindowSeconds = 3_600

    public let maxRunning: Int
    public let maxVcpu: Int
    public let maxRamMb: Int
    public let maxSandboxesPerHour: Int

    public init(maxRunning: Int = defaultMaxRunning, maxVcpu: Int = defaultMaxVcpu, maxRamMb: Int = defaultMaxRamMb,
                maxSandboxesPerHour: Int = defaultMaxSandboxesPerHour) {
        self.maxRunning = maxRunning
        self.maxVcpu = maxVcpu
        self.maxRamMb = maxRamMb
        self.maxSandboxesPerHour = maxSandboxesPerHour
    }

    public static let standard = TeamLimits()
}

/// What a team already uses: the running sandboxes, what they hold, and how many were made in the last hour.
public struct TeamUsage: Equatable, Sendable {
    public let running: Int
    public let vcpu: Int
    public let ramMb: Int
    public let createdLastHour: Int

    public init(running: Int, vcpu: Int, ramMb: Int, createdLastHour: Int) {
        self.running = running
        self.vcpu = vcpu
        self.ramMb = ramMb
        self.createdLastHour = createdLastHour
    }
}

/// Which of a team's limits a create would break. Each is distinct, so a caller can say exactly what is full instead of
/// a generic "bad request".
public enum TeamLimitReason: String, Error, Equatable, CaseIterable, Sendable {
    case tooManyRunning = "too_many_running"
    case tooMuchVcpu = "too_much_vcpu"
    case tooMuchRam = "too_much_ram"
    case tooManyPerHour = "too_many_per_hour"
}

/// A create that a team's limits refuse, with the numbers that explain it.
public struct TeamLimitRefusal: Error, Equatable, Sendable {
    public let reason: TeamLimitReason
    public let message: String
    public let limit: Int
    public let used: Int
    public let needed: Int

    public init(reason: TeamLimitReason, message: String, limit: Int, used: Int, needed: Int) {
        self.reason = reason
        self.message = message
        self.limit = limit
        self.used = used
        self.needed = needed
    }
}

/// The team's limits against what it already uses, for one sandbox of a given shape. Exactly at a limit still fits; one
/// more does not.
public enum SandboxLimits {
    public static func refusal(_ limits: TeamLimits, usage: TeamUsage, shape: SandboxShape) -> TeamLimitRefusal? {
        if usage.running >= limits.maxRunning {
            return TeamLimitRefusal(reason: .tooManyRunning, message: "This team already runs \(usage.running) sandboxes at once, its limit.",
                                    limit: limits.maxRunning, used: usage.running, needed: 1)
        }
        if usage.vcpu + shape.vcpu > limits.maxVcpu {
            return TeamLimitRefusal(reason: .tooMuchVcpu, message: "This team's running sandboxes already use \(usage.vcpu) of its \(limits.maxVcpu) vCPU.",
                                    limit: limits.maxVcpu, used: usage.vcpu, needed: shape.vcpu)
        }
        if usage.ramMb + shape.ramMb > limits.maxRamMb {
            return TeamLimitRefusal(reason: .tooMuchRam, message: "This team's running sandboxes already use \(usage.ramMb) MB of its \(limits.maxRamMb) MB.",
                                    limit: limits.maxRamMb, used: usage.ramMb, needed: shape.ramMb)
        }
        if usage.createdLastHour >= limits.maxSandboxesPerHour {
            return TeamLimitRefusal(reason: .tooManyPerHour, message: "This team has made \(usage.createdLastHour) sandboxes in the last hour, its limit.",
                                    limit: limits.maxSandboxesPerHour, used: usage.createdLastHour, needed: 1)
        }
        return nil
    }
}
