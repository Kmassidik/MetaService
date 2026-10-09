import Foundation
import MSCore

/// Everything the Add machine form says about a machine besides its name: what kind it is, how it may be used, and what its VMs get by default.
/// Checked at the door, stored with the machine, and used when VMs are placed and created.
public struct MachineSettings: Codable, Equatable {
    public static let profiles: Set<String> = ["apple-silicon-mac", "linux-x86", "linux-arm", "gpu-box", "custom"]
    public static let maxLabels = 8

    public var profile: String
    public var labels: [String]
    public var notes: String
    public var ramReserveMb: Int?
    public var diskReserveGb: Int?
    public var ramAllowanceMb: Int?
    public var diskAllowanceGb: Int?
    public var allowGpu: Bool
    public var vmCpu: Int?
    public var vmRamMb: Int?
    public var vmDiskGb: Int?
    public var vmImage: String?
    public var vmMaxRunning: Int?
    public var subdomain: String?
    public var publicChat: Bool
    public var aiModel: String?

    public static let fields: Set<String> = ["profile", "labels", "notes", "ram_reserve_mb", "disk_reserve_gb", "ram_allowance_mb", "disk_allowance_gb", "allow_gpu",
                                             "vm_cpu", "vm_ram_mb", "vm_disk_gb", "vm_image", "vm_max_running", "subdomain", "public_chat", "ai_model"]
    private static let labelPattern = #/^[a-z0-9][a-z0-9-]{0,29}$/#
    private static let subdomainPattern = #/^[a-z0-9][a-z0-9-]{0,30}$/#
    private static let imagePattern = #/^[a-z0-9][a-z0-9._:\/-]{0,127}$/#
    private static let modelPattern = #/^[A-Za-z0-9][A-Za-z0-9._:\/-]{0,99}$/#

    public init(profile: String = "custom", labels: [String] = [], notes: String = "", ramReserveMb: Int? = nil, diskReserveGb: Int? = nil, ramAllowanceMb: Int? = nil,
                diskAllowanceGb: Int? = nil, allowGpu: Bool = true, vmCpu: Int? = nil, vmRamMb: Int? = nil, vmDiskGb: Int? = nil, vmImage: String? = nil,
                vmMaxRunning: Int? = nil, subdomain: String? = nil, publicChat: Bool = false, aiModel: String? = nil) {
        self.profile = profile
        self.labels = labels
        self.notes = notes
        self.ramReserveMb = ramReserveMb
        self.diskReserveGb = diskReserveGb
        self.ramAllowanceMb = ramAllowanceMb
        self.diskAllowanceGb = diskAllowanceGb
        self.allowGpu = allowGpu
        self.vmCpu = vmCpu
        self.vmRamMb = vmRamMb
        self.vmDiskGb = vmDiskGb
        self.vmImage = vmImage
        self.vmMaxRunning = vmMaxRunning
        self.subdomain = subdomain
        self.publicChat = publicChat
        self.aiModel = aiModel
    }

    /// What the machine may be used for: with GPU use switched off, the machine does not offer its GPU to VMs or containers.
    public func limiting(_ capabilities: Capabilities?) -> Capabilities? {
        guard !allowGpu, let capabilities else { return capabilities }
        return Capabilities(vm: capabilities.vm, container: capabilities.container, gpuInVm: false, gpuInContainer: false)
    }

    /// True when the machine already runs as many VMs as it was allowed.
    public func isFull(running: Int) -> Bool {
        vmMaxRunning.map { running >= $0 } ?? false
    }

    /// Reads the settings out of the request's fields. Anything missing takes the default; anything odd is refused.
    public init(_ object: StrictObject) throws {
        profile = object.has("profile") ? try object.choice("profile", among: Self.profiles) : "custom"
        labels = object.has("labels") ? try object.strings("labels", maxCount: Self.maxLabels, pattern: Self.labelPattern, maxLength: 30) : []
        guard Set(labels).count == labels.count else { throw InputError("labels must be different from each other") }
        notes = try object.optionalString("notes", maxLength: 300) ?? ""
        ramReserveMb = object.has("ram_reserve_mb") ? try object.int("ram_reserve_mb", range: 0...10_000_000) : nil
        diskReserveGb = object.has("disk_reserve_gb") ? try object.int("disk_reserve_gb", range: 0...10_000_000) : nil
        ramAllowanceMb = object.has("ram_allowance_mb") ? try object.int("ram_allowance_mb", range: 512...10_000_000) : nil
        diskAllowanceGb = object.has("disk_allowance_gb") ? try object.int("disk_allowance_gb", range: 1...10_000_000) : nil
        allowGpu = object.has("allow_gpu") ? try object.bool("allow_gpu") : true
        vmCpu = object.has("vm_cpu") ? try object.int("vm_cpu", range: 1...64) : nil
        vmRamMb = object.has("vm_ram_mb") ? try object.int("vm_ram_mb", range: 512...1_048_576) : nil
        vmDiskGb = object.has("vm_disk_gb") ? try object.int("vm_disk_gb", range: 1...100_000) : nil
        vmImage = object.has("vm_image") ? try object.string("vm_image", pattern: Self.imagePattern, maxLength: 128, minLength: 1) : nil
        vmMaxRunning = object.has("vm_max_running") ? try object.int("vm_max_running", range: 1...1000) : nil
        subdomain = object.has("subdomain") ? try object.string("subdomain", pattern: Self.subdomainPattern, maxLength: 31, minLength: 1) : nil
        publicChat = object.has("public_chat") ? try object.bool("public_chat") : false
        aiModel = object.has("ai_model") ? try object.string("ai_model", pattern: Self.modelPattern, maxLength: 100, minLength: 1) : nil
        if let allowance = ramAllowanceMb, let reserve = ramReserveMb, reserve >= allowance { throw InputError("the memory kept free must be smaller than the most it may use") }
        if let allowance = diskAllowanceGb, let reserve = diskReserveGb, reserve >= allowance { throw InputError("the disk kept free must be smaller than the most it may use") }
    }
}
