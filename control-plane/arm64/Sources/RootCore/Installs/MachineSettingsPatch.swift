import Foundation
import MSCore

/// A change to a machine's settings after it was added: only what the machine page lets a person edit. Everything else is refused, not ignored.
/// A field that is not mentioned stays as it was; a field set to null is cleared (only the ones that can be empty).
public struct MachineSettingsPatch {
    public static let fields: Set<String> = ["name", "labels", "notes", "allow_gpu", "ram_reserve_mb", "disk_reserve_gb", "ram_allowance_mb", "disk_allowance_gb",
                                             "vm_max_running", "vm_cpu", "vm_ram_mb", "vm_disk_gb", "vm_image", "subdomain", "ai_model", "ssh_jump"]

    /// The new name of the machine, when the person changed it.
    public let name: String?
    /// The names of the fields that change, in order. Safe to write in the audit log: it holds no values.
    public let changed: [String]
    private let object: StrictObject
    /// Fields that always hold something cannot be cleared.
    private static let neverEmpty = ["name", "labels", "notes", "allow_gpu"]

    public init(body: Data) throws {
        let parsed = try StrictObject(data: body, allowed: Self.fields)
        if let key = Self.neverEmpty.first(where: parsed.isNull) { throw InputError("\(key) cannot be empty") }
        guard !parsed.keys.isEmpty else { throw InputError("say at least one thing to change") }
        object = parsed
        changed = parsed.keys.sorted()
        name = parsed.has("name") ? try parsed.id("name") : nil
        _ = try applying(to: MachineSettings())
    }

    /// The settings after the change. Checked as a whole, so a new "most it may use" is compared with the "kept free" that was already there.
    public func applying(to current: MachineSettings) throws -> MachineSettings {
        var next = current
        try changeTexts(&next)
        try changeLimits(&next)
        try changeVmDefaults(&next)
        try next.checkReserves()
        return next
    }

    private func changeTexts(_ settings: inout MachineSettings) throws {
        if object.has("labels") {
            settings.labels = try object.strings("labels", maxCount: MachineSettings.maxLabels, pattern: MachineSettings.labelPattern, maxLength: MachineSettings.maxLabelLength)
            guard Set(settings.labels).count == settings.labels.count else { throw InputError("labels must be different from each other") }
        }
        if object.has("notes") { settings.notes = try object.string("notes", maxLength: MachineSettings.maxNotes) }
        if object.has("allow_gpu") { settings.allowGpu = try object.bool("allow_gpu") }
        try change(&settings.subdomain, "subdomain") { try object.string("subdomain", pattern: MachineSettings.subdomainPattern, maxLength: MachineSettings.maxSubdomainLength, minLength: 1) }
        try change(&settings.sshJump, "ssh_jump") { try MachineSettings.checkedJump(object.string("ssh_jump", maxLength: SshConnect.maxJumpCharacters, minLength: 1)) }
        try change(&settings.aiModel, "ai_model") { try object.string("ai_model", pattern: MachineSettings.modelPattern, maxLength: MachineSettings.maxModelLength, minLength: 1) }
    }

    private func changeLimits(_ settings: inout MachineSettings) throws {
        try changeNumber(&settings.ramReserveMb, "ram_reserve_mb", MachineSettings.ramReserveRange)
        try changeNumber(&settings.diskReserveGb, "disk_reserve_gb", MachineSettings.diskReserveRange)
        try changeNumber(&settings.ramAllowanceMb, "ram_allowance_mb", MachineSettings.ramAllowanceRange)
        try changeNumber(&settings.diskAllowanceGb, "disk_allowance_gb", MachineSettings.diskAllowanceRange)
        try changeNumber(&settings.vmMaxRunning, "vm_max_running", MachineSettings.vmMaxRunningRange)
    }

    private func changeVmDefaults(_ settings: inout MachineSettings) throws {
        try changeNumber(&settings.vmCpu, "vm_cpu", MachineSettings.vmCpuRange)
        try changeNumber(&settings.vmRamMb, "vm_ram_mb", MachineSettings.vmRamRange)
        try changeNumber(&settings.vmDiskGb, "vm_disk_gb", MachineSettings.vmDiskRange)
        try change(&settings.vmImage, "vm_image") { try object.string("vm_image", pattern: MachineSettings.imagePattern, maxLength: MachineSettings.maxImageLength, minLength: 1) }
    }

    private func changeNumber(_ target: inout Int?, _ key: String, _ range: ClosedRange<Int>) throws {
        try change(&target, key) { try object.int(key, range: range) }
    }

    /// Mentioned with a value: set. Mentioned as null: cleared. Not mentioned: left alone.
    private func change<Value>(_ target: inout Value?, _ key: String, read: () throws -> Value) throws {
        if object.isNull(key) { target = nil }
        if object.has(key) { target = try read() }
    }

}
