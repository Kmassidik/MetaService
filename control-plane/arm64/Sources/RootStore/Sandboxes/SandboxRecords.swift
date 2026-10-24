import Foundation
import RootCore

/// A sandbox team as the panel sees it: its name, when it was made, and its limits. Never a secret.
public struct TeamRecord: Encodable, Equatable {
    public let id: String
    public let name: String
    public let createdAt: Date
    public let limits: TeamLimits

    public init(id: String, name: String, createdAt: Date, limits: TeamLimits) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.limits = limits
    }

    enum CodingKeys: String, CodingKey { case id, name, createdAt, limits }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(name, forKey: .name)
        try box.encode(Dates.iso(Int(createdAt.timeIntervalSince1970)), forKey: .createdAt)
        try box.encode(limits, forKey: .limits)
    }
}

/// One API key as the panel sees it. The key text and its secret are not here, and its hash is not shown either: the
/// prefix is enough to tell two keys apart, and nothing shown can be used to call the API.
public struct ApiKeyRecord: Encodable, Equatable {
    public let id: String
    public let team: String
    public let prefix: String
    public let createdAt: Date
    public let lastUsedAt: Date?
    public let revokedAt: Date?

    public init(id: String, team: String, prefix: String, createdAt: Date, lastUsedAt: Date?, revokedAt: Date?) {
        self.id = id
        self.team = team
        self.prefix = prefix
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.revokedAt = revokedAt
    }

    public var isRevoked: Bool { revokedAt != nil }

    enum CodingKeys: String, CodingKey { case id, team, prefix, createdAt, lastUsedAt, revokedAt }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(team, forKey: .team)
        try box.encode(prefix, forKey: .prefix)
        try box.encode(Dates.iso(Int(createdAt.timeIntervalSince1970)), forKey: .createdAt)
        try box.encode(lastUsedAt.map { Dates.iso(Int($0.timeIntervalSince1970)) }, forKey: .lastUsedAt)
        try box.encode(revokedAt.map { Dates.iso(Int($0.timeIntervalSince1970)) }, forKey: .revokedAt)
    }
}

/// One sandbox, from the moment it is accepted until it ends. The record outlives the sandbox, so the list and the usage
/// stay readable after the helper is done with it.
public struct SandboxRecord: Encodable, Equatable {
    public let id: String
    public let team: String
    public let machine: String
    public let state: SandboxState
    public let template: String
    public let vcpu: Int
    public let ramMb: Int
    public let diskMb: Int
    public let createdAt: Date
    public let endAt: Date
    public let endedAt: Date?
    public let endedReason: SandboxEndReason?

    public init(id: String, team: String, machine: String, state: SandboxState, template: String, vcpu: Int, ramMb: Int, diskMb: Int,
                createdAt: Date, endAt: Date, endedAt: Date? = nil, endedReason: SandboxEndReason? = nil) {
        self.id = id
        self.team = team
        self.machine = machine
        self.state = state
        self.template = template
        self.vcpu = vcpu
        self.ramMb = ramMb
        self.diskMb = diskMb
        self.createdAt = createdAt
        self.endAt = endAt
        self.endedAt = endedAt
        self.endedReason = endedReason
    }

    public var shape: SandboxShape { SandboxShape(vcpu: vcpu, ramMb: ramMb, diskMb: diskMb) }
    public var isAlive: Bool { state.isAlive }

    /// Whole seconds left before the end time, never negative.
    public func remainingSeconds(now: Date) -> Int { SandboxEndTime.remainingSeconds(until: endAt, now: now) }

    enum CodingKeys: String, CodingKey {
        case id, team, machine, state, template, vcpu, ramMb, diskMb, createdAt, endAt, endedAt, endedReason
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(team, forKey: .team)
        try box.encode(machine, forKey: .machine)
        try box.encode(state.rawValue, forKey: .state)
        try box.encode(template, forKey: .template)
        try box.encode(vcpu, forKey: .vcpu)
        try box.encode(ramMb, forKey: .ramMb)
        try box.encode(diskMb, forKey: .diskMb)
        try box.encode(Dates.iso(Int(createdAt.timeIntervalSince1970)), forKey: .createdAt)
        try box.encode(Dates.iso(Int(endAt.timeIntervalSince1970)), forKey: .endAt)
        try box.encode(endedAt.map { Dates.iso(Int($0.timeIntervalSince1970)) }, forKey: .endedAt)
        try box.encode(endedReason?.rawValue, forKey: .endedReason)
    }
}

/// What a create must say: the id the parent picked, the team buying it, where it goes, and how it is shaped.
public struct NewSandbox: Equatable {
    public let id: String
    public let team: String
    public let machine: String
    public let template: String
    public let shape: SandboxShape
    public let endAt: Date
    public let state: SandboxState

    public init(id: String, team: String, machine: String, template: String, shape: SandboxShape, endAt: Date,
                state: SandboxState = .starting) {
        self.id = id
        self.team = team
        self.machine = machine
        self.template = template
        self.shape = shape
        self.endAt = endAt
        self.state = state
    }
}
