import Foundation

/// What a helper checked about the machine's own settings. Every field is nil when the helper does not know; nil is never turned into false or zero.
public struct SecurityBaseline: Codable, Equatable, Sendable {
    public static let banToolStates = ["running", "not_running", "not_available"]
    private static let maxPendingUpdates = 100_000

    public var passwordLogin: Bool?
    public var banTool: String?
    public var firewall: Bool?
    public var autoUpdates: Bool?
    public var startsAfterReboot: Bool?
    public var pendingUpdates: Int?

    public static let unknown = SecurityBaseline()

    public init(passwordLogin: Bool? = nil, banTool: String? = nil, firewall: Bool? = nil, autoUpdates: Bool? = nil, startsAfterReboot: Bool? = nil, pendingUpdates: Int? = nil) {
        self.passwordLogin = passwordLogin
        self.banTool = banTool
        self.firewall = firewall
        self.autoUpdates = autoUpdates
        self.startsAfterReboot = startsAfterReboot
        self.pendingUpdates = pendingUpdates
    }

    enum CodingKeys: String, CodingKey {
        case passwordLogin = "password_login", banTool = "ban_tool", firewall, autoUpdates = "auto_updates", startsAfterReboot = "starts_after_reboot", pendingUpdates = "pending_updates"
    }

    /// Reads the helper's `baseline` object, field by field: a field of the wrong type or outside its range is nil.
    public init(helper value: Any?) {
        let object = value as? [String: Any] ?? [:]
        self.init(passwordLogin: Self.flag(object["password_login"]),
                  banTool: (object["ban_tool"] as? String).flatMap { Self.banToolStates.contains($0) ? $0 : nil },
                  firewall: Self.flag(object["firewall"]), autoUpdates: Self.flag(object["auto_updates"]),
                  startsAfterReboot: Self.flag(object["starts_after_reboot"]), pendingUpdates: Self.count(object["pending_updates"]))
    }

    /// Every key is written, null included, so a reader can tell "unknown" from "left out by mistake".
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(passwordLogin, forKey: .passwordLogin)
        try box.encode(banTool, forKey: .banTool)
        try box.encode(firewall, forKey: .firewall)
        try box.encode(autoUpdates, forKey: .autoUpdates)
        try box.encode(startsAfterReboot, forKey: .startsAfterReboot)
        try box.encode(pendingUpdates, forKey: .pendingUpdates)
    }

    private static func isBoolean(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }

    private static func flag(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    private static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBoolean(number), let whole = Int(exactly: number.doubleValue), (0...maxPendingUpdates).contains(whole) else { return nil }
        return whole
    }
}
