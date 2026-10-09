import Foundation
import RootCore

/// The settings each machine was installed with. Kept as one JSON text per machine, read back through the same checked type.
public struct MachineSettingsStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    public func save(_ settings: MachineSettings, machine: String) throws {
        let json = String(data: try JSONEncoder().encode(settings), encoding: .utf8) ?? "{}"
        try database.execute("INSERT OR REPLACE INTO machine_settings (machine, settings_json) VALUES (?, ?)", [.text(machine), .text(json)])
    }

    public func get(machine: String) throws -> MachineSettings? {
        try database.query("SELECT settings_json FROM machine_settings WHERE machine = ?", [.text(machine)]).first.flatMap {
            try? JSONDecoder().decode(MachineSettings.self, from: Data($0.string("settings_json").utf8))
        }
    }

    public func remove(machine: String) throws {
        try database.execute("DELETE FROM machine_settings WHERE machine = ?", [.text(machine)])
    }
}
