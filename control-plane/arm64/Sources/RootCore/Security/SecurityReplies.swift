import Foundation

/// The JSON of the two Security routes. Optional values are written as null, never left out; the encoder turns names into snake_case.
public struct SecurityMachineLine: Encodable, Equatable, Sendable {
    public let machine: String
    public let reported: Bool
    public let lastReported: String?
    public let baseline: SecurityBaseline
    public let failed: Int?
    public let blocked: Int?

    public init(machine: String, reported: Bool, lastReported: String?, baseline: SecurityBaseline, failed: Int?, blocked: Int?) {
        self.machine = machine
        self.reported = reported
        self.lastReported = lastReported
        self.baseline = baseline
        self.failed = failed
        self.blocked = blocked
    }

    /// A machine nobody watches: no data, no numbers, never zero.
    public static func notWatched(_ machine: String) -> SecurityMachineLine {
        SecurityMachineLine(machine: machine, reported: false, lastReported: nil, baseline: .unknown, failed: nil, blocked: nil)
    }

    enum CodingKeys: String, CodingKey { case machine, reported, lastReported, baseline, failed, blocked }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(machine, forKey: .machine)
        try box.encode(reported, forKey: .reported)
        try box.encode(lastReported, forKey: .lastReported)
        try box.encode(baseline, forKey: .baseline)
        try box.encode(failed, forKey: .failed)
        try box.encode(blocked, forKey: .blocked)
    }
}

public struct SecurityBlockedRow: Encodable, Equatable, Sendable {
    public let machine: String
    public let address: String
    public let since: String
    public let until: String?
    public let attempts: Int?

    public init(machine: String, address: String, since: String, until: String?, attempts: Int?) {
        self.machine = machine
        self.address = address
        self.since = since
        self.until = until
        self.attempts = attempts
    }

    enum CodingKeys: String, CodingKey { case machine, address, since, until, attempts }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(machine, forKey: .machine)
        try box.encode(address, forKey: .address)
        try box.encode(since, forKey: .since)
        try box.encode(until, forKey: .until)
        try box.encode(attempts, forKey: .attempts)
    }
}

public struct SecurityTopRow: Encodable, Equatable, Sendable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct SecurityDailyRow: Encodable, Equatable, Sendable {
    public let day: String
    public let machine: String
    public let failed: Int

    public init(day: String, machine: String, failed: Int) {
        self.day = day
        self.machine = machine
        self.failed = failed
    }
}

/// Failed logins of one machine in one ten-minute bucket; a bucket without a count has no row.
public struct SecurityBucketRow: Encodable, Equatable, Sendable {
    public let start: String
    public let machine: String
    public let failed: Int

    public init(start: String, machine: String, failed: Int) {
        self.start = start
        self.machine = machine
        self.failed = failed
    }
}

public struct SecurityOverviewReply: Encodable, Equatable, Sendable {
    public let range: String
    public let generatedAt: String
    public let machines: [SecurityMachineLine]
    public let blockedNow: [SecurityBlockedRow]
    public let topUsers: [SecurityTopRow]
    public let topAddresses: [SecurityTopRow]
    public let daily: [SecurityDailyRow]
    /// Ten-minute counts for ranges up to 24 hours; empty for longer ranges, which use `daily`.
    public let buckets: [SecurityBucketRow]
    public let bucketMinutes: Int

    public init(range: String, generatedAt: String, machines: [SecurityMachineLine], blockedNow: [SecurityBlockedRow], topUsers: [SecurityTopRow], topAddresses: [SecurityTopRow],
                daily: [SecurityDailyRow], buckets: [SecurityBucketRow] = [], bucketMinutes: Int = SecurityTime.bucketMinutes) {
        self.range = range
        self.generatedAt = generatedAt
        self.machines = machines
        self.blockedNow = blockedNow
        self.topUsers = topUsers
        self.topAddresses = topAddresses
        self.daily = daily
        self.buckets = buckets
        self.bucketMinutes = bucketMinutes
    }
}

public struct SecurityEventRow: Encodable, Equatable, Sendable {
    public let id: String
    public let time: String
    public let machine: String
    public let type: String
    public let user: String?
    public let address: String?
    public let detail: String?
    public let method: String?
    public let count: Int?

    public init(id: String, time: String, machine: String, type: String, user: String?, address: String?, detail: String?, method: String?, count: Int?) {
        self.id = id
        self.time = time
        self.machine = machine
        self.type = type
        self.user = user
        self.address = address
        self.detail = detail
        self.method = method
        self.count = count
    }

    enum CodingKeys: String, CodingKey { case id, time, machine, type, user, address, detail, method, count }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(time, forKey: .time)
        try box.encode(machine, forKey: .machine)
        try box.encode(type, forKey: .type)
        try box.encode(user, forKey: .user)
        try box.encode(address, forKey: .address)
        try box.encode(detail, forKey: .detail)
        try box.encode(method, forKey: .method)
        try box.encode(count, forKey: .count)
    }
}

public struct SecurityEventsReply: Encodable, Equatable, Sendable {
    public let events: [SecurityEventRow]
    public let total: Int
    public let page: Int
    public let pageSize: Int

    public init(events: [SecurityEventRow], total: Int, page: Int, pageSize: Int) {
        self.events = events
        self.total = total
        self.page = page
        self.pageSize = pageSize
    }
}
