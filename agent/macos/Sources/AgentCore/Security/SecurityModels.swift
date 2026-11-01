import Foundation

/// The JSON of `GET /v1/security/events`, exactly as the parent's contract writes it. Optional fields are written as `null`, never left out.
public enum SecurityEventType: String, Encodable, Equatable { case failedLogin = "failed_login", login, blocked, unblocked }
public enum SecurityMethod: String, Encodable, Equatable { case key, password }
public enum BanTool: String, Encodable, Equatable { case running, notRunning = "not_running", notAvailable = "not_available" }

public struct SecurityEvent: Encodable, Equatable {
    public let time: String
    public let type: SecurityEventType
    public let user: String?
    public let address: String?
    public let method: SecurityMethod?
    public let count: Int
    public let until: String?
    public let detail: String?

    public init(time: String, type: SecurityEventType, user: String? = nil, address: String? = nil, method: SecurityMethod? = nil, count: Int = 1, until: String? = nil, detail: String? = nil) {
        self.time = time; self.type = type; self.user = user; self.address = address; self.method = method; self.count = count; self.until = until; self.detail = detail
    }

    enum CodingKeys: String, CodingKey { case time, type, user, address, method, count, until, detail }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(time, forKey: .time)
        try box.encode(type, forKey: .type)
        try box.encode(user, forKey: .user)
        try box.encode(address, forKey: .address)
        try box.encode(method, forKey: .method)
        try box.encode(count, forKey: .count)
        try box.encode(until, forKey: .until)
        try box.encode(detail, forKey: .detail)
    }
}

/// The machine's baseline settings. A field is `nil` (written as `null`) when this helper could not tell.
public struct SecurityBaseline: Encodable, Equatable {
    public var passwordLogin: Bool?
    public var banTool: BanTool?
    public var firewall: Bool?
    public var autoUpdates: Bool?
    public var startsAfterReboot: Bool?
    public var pendingUpdates: Int?

    public init(passwordLogin: Bool? = nil, banTool: BanTool? = nil, firewall: Bool? = nil, autoUpdates: Bool? = nil, startsAfterReboot: Bool? = nil, pendingUpdates: Int? = nil) {
        self.passwordLogin = passwordLogin; self.banTool = banTool; self.firewall = firewall
        self.autoUpdates = autoUpdates; self.startsAfterReboot = startsAfterReboot; self.pendingUpdates = pendingUpdates
    }

    enum CodingKeys: String, CodingKey { case passwordLogin, banTool, firewall, autoUpdates, startsAfterReboot, pendingUpdates }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(passwordLogin, forKey: .passwordLogin)
        try box.encode(banTool, forKey: .banTool)
        try box.encode(firewall, forKey: .firewall)
        try box.encode(autoUpdates, forKey: .autoUpdates)
        try box.encode(startsAfterReboot, forKey: .startsAfterReboot)
        try box.encode(pendingUpdates, forKey: .pendingUpdates)
    }
}

public struct SecurityAnswer: Encodable, Equatable {
    public let cursor: String
    public let reset: Bool
    public let events: [SecurityEvent]
    public let baseline: SecurityBaseline

    public init(cursor: String, reset: Bool, events: [SecurityEvent], baseline: SecurityBaseline) {
        self.cursor = cursor; self.reset = reset; self.events = events; self.baseline = baseline
    }
}

/// The log could not be read at all (the `log` tool is missing, or it failed or timed out before anything was read).
public struct SecurityLogFailure: Error, Equatable {
    public static let errorCode = "security_log_failed"
    public let message: String
    public init(_ message: String) { self.message = message }
}
