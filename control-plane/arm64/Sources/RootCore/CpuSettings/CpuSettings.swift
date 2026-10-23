import Foundation

/// The CPU settings of a new VM or container, as in Proxmox's Processors window: sockets, the CPU type and CPU flags for a VM, a hard CPU limit for a container.
/// Pure rules: what a helper may say it offers, what a create may ask for, and the plain reason when a machine cannot give it. Names and limits follow contract/openapi.yaml.
public enum CpuSettings {
    /// The machine's own CPU: what every VM got before these settings.
    public static let hostModel = "host"
    /// What a helper that does not say offers: the host CPU only.
    public static let defaultModels = [hostModel]
    public static let flagNames: Set<String> = ["nested-virt", "aes"]
    public static let allowedSockets = 1...8
    /// In percent of one core: 150 is one and a half cores.
    public static let allowedLimitPercent = 10...6400
    static let percentPerCore = 100
    static let maxModels = 64
    static let maxModelLength = 40
    static let maxFlags = 8
    static let modelPattern = #/^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/#
    static let flagValues: Set<String> = ["on", "off"]
    static let missingCode = "missing_capability"

    // MARK: what a helper offers

    /// The CPU models a helper lists, each of the model shape, at most 64 and none twice.
    static func offeredModels(_ capabilities: StrictObject) throws -> [String] {
        let models = try capabilities.strings("cpu_models", maxCount: maxModels, pattern: modelPattern, maxLength: maxModelLength)
        guard Set(models).count == models.count else { throw InputError("facts/capabilities/cpu_models must be different from each other") }
        return models
    }

    /// The CPU flags a helper lists: only the ones the contract names, none twice.
    static func offeredFlags(_ capabilities: StrictObject) throws -> [String] {
        let flags = try capabilities.strings("cpu_flags", maxCount: maxFlags, pattern: modelPattern, maxLength: maxModelLength)
        guard flags.allSatisfy(flagNames.contains) else { throw InputError("facts/capabilities/cpu_flags may only list nested-virt and aes") }
        guard Set(flags).count == flags.count else { throw InputError("facts/capabilities/cpu_flags must be different from each other") }
        return flags
    }

    // MARK: what a create asks for

    /// How many sockets a VM's CPUs are spread over; `cpu` must split evenly over them. One socket is what every VM got before, so it reads as nil.
    static func sockets(_ body: StrictObject, kind: String, cpu: Int) throws -> Int? {
        guard body.has("cpu_sockets") else { return nil }
        let sockets = try body.int("cpu_sockets", range: allowedSockets)
        guard kind == "vm" else { throw InputError("cpu_sockets can only be set when kind is vm") }
        guard cpu % sockets == 0 else { throw InputError("cpu must be a multiple of cpu_sockets") }
        return sockets == 1 ? nil : sockets
    }

    /// The CPU model a VM sees. Whether the machine knows it is decided when the machine is chosen. `host` is what every VM got before, so it reads as nil.
    static func type(_ body: StrictObject, kind: String) throws -> String? {
        guard body.has("cpu_type") else { return nil }
        let type = try body.string("cpu_type", pattern: modelPattern, maxLength: maxModelLength, minLength: 1)
        guard kind == "vm" else { throw InputError("cpu_type can only be set when kind is vm") }
        return type == hostModel ? nil : type
    }

    /// CPU flags switched `on` or `off` for a VM, by name; a flag left out keeps what the CPU type gives. When the field is there it names at least one flag.
    static func flags(_ body: StrictObject, kind: String) throws -> [String: String]? {
        guard body.has("cpu_flags") else { return nil }
        let object = try body.object("cpu_flags", allowed: flagNames)
        let flags = try Dictionary(uniqueKeysWithValues: object.keys.map { ($0, try object.choice($0, among: flagValues)) })
        guard !flags.isEmpty else { throw InputError("cpu_flags must name at least one flag") }
        guard kind == "vm" else { throw InputError("cpu_flags can only be set when kind is vm") }
        return flags
    }

    /// A hard cap on a container's CPU time, in percent of one core, at most all of its cores.
    static func limitPercent(_ body: StrictObject, kind: String, cpu: Int) throws -> Int? {
        guard body.has("cpu_limit_percent") else { return nil }
        let percent = try body.int("cpu_limit_percent", range: allowedLimitPercent)
        guard kind == "container" else { throw InputError("cpu_limit_percent can only be set when kind is container") }
        guard percent <= cpu * percentPerCore else { throw InputError("cpu_limit_percent can be at most cpu x 100") }
        return percent
    }

    /// The flags asked for as one short line, by name, for the audit: `aes off, nested-virt on`.
    public static func flagsText(_ flags: [String: String]) -> String {
        flags.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }

    // MARK: what a machine can give

    /// Why a machine cannot give the CPU settings a wish asks for, or nil when it can. A machine that does not say what it can do offers only what every VM got before.
    public static func refusal(_ capabilities: Capabilities?, _ wish: PlacementWish) -> PlacementRefusal? {
        missing(capabilities, wish).map { PlacementRefusal(code: missingCode, message: $0, resource: "capability", needed: 1, free: 0) }
    }

    /// The first setting asked for that the machine does not offer, in plain words with what to do instead.
    static func missing(_ offer: Capabilities?, _ wish: PlacementWish) -> String? {
        if let sockets = wish.cpuSockets, sockets > 1, offer?.cpuTopology != true {
            return "This machine cannot give a VM more than one socket. Update its helper, or pick 1 socket."
        }
        if let type = wish.cpuType, offer?.cpuModels.contains(type) != true {
            return "This machine cannot set the CPU type \(type). Update its helper, or pick host."
        }
        if let flag = wish.cpuFlags?.keys.sorted().first(where: { offer?.cpuFlags.contains($0) != true }) {
            return "This machine cannot switch the \(flag) flag. Update its helper, or leave the flag on Default."
        }
        if wish.cpuLimitPercent != nil, offer?.cpuLimit != true {
            return "This machine cannot cap a container's CPU time. Update its helper, or leave the CPU limit empty."
        }
        return nil
    }
}
