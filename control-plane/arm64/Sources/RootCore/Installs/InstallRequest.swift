import Foundation
import MSCore

/// What the Add machine form sends: install MetaService on this computer, with or without the chat, with the room it must leave for the system.
/// Installing on another computer (by IP over SSH) comes later; `target` already names the choice so the form does not change.
public struct InstallRequest: Equatable {
    public let name: String
    public let chat: Bool
    public let ramReserveMb: Int?
    public let diskReserveGb: Int?

    public static let maxRamReserveMb = 10_000_000
    public static let maxDiskReserveGb = 10_000_000

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["target", "name", "chat", "ram_reserve_mb", "disk_reserve_gb"])
        _ = try object.choice("target", among: ["this"])
        name = try object.id("name")
        chat = try object.bool("chat")
        ramReserveMb = object.has("ram_reserve_mb") ? try object.int("ram_reserve_mb", range: 0...Self.maxRamReserveMb) : nil
        diskReserveGb = object.has("disk_reserve_gb") ? try object.int("disk_reserve_gb", range: 0...Self.maxDiskReserveGb) : nil
    }
}

/// The room the Add machine form suggests to keep for the system (the same rule the Agent uses when nothing is said): a quarter of the memory
/// but at least 4 GB, and a fifth of the disk but at least 30 GB, never more than half of what the computer has.
public enum InstallDefaults {
    public static func ramReserveMb(totalMb: Int) -> Int { min(max(4096, totalMb / 4), totalMb / 2) }
    public static func diskReserveGb(totalGb: Int) -> Int { min(max(30, totalGb / 5), totalGb / 2) }
}

public enum InstallState: String, Encodable {
    case pending, running, done, failed
}

public struct InstallStep: Encodable, Equatable {
    public let id: String
    public let label: String
    public var state: InstallState
    public var detail: String?

    public init(id: String, label: String, state: InstallState = .pending, detail: String? = nil) {
        self.id = id
        self.label = label
        self.state = state
        self.detail = detail
    }

    /// The steps of one install, in order. The chat step exists only when the chat was asked for.
    public static func plan(chat: Bool) -> [InstallStep] {
        var steps = [InstallStep(id: "check", label: "Check the request"), InstallStep(id: "agent", label: "Install and start MetaService on this computer"),
                     InstallStep(id: "online", label: "Wait for the machine to report in")]
        if chat { steps.append(InstallStep(id: "chat", label: "Install the chat")) }
        return steps
    }
}
