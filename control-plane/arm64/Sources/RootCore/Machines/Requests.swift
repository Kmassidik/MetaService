import Foundation

/// The bodies Agents and operators send, parsed strictly. Field names and limits follow contract/openapi.yaml.

public struct EnrollRequest: Equatable {
    public let enrollmentToken: String
    public let name: String

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["enrollment_token", "name"])
        enrollmentToken = try object.string("enrollment_token", maxLength: 256, minLength: 16)
        name = try object.id("name")
    }
}

public struct GpuInfo: Equatable, Codable {
    public let vendor: String
    public let model: String
    public let memoryMb: Int?
}

/// Something on the machine itself that stops it from running workloads, with the way to fix it. Reported by the Agent in its facts.
public struct HostProblem: Equatable, Codable {
    public let code: String
    public let message: String
    public let fix: String

    public init(code: String, message: String, fix: String) {
        self.code = code
        self.message = message
        self.fix = fix
    }
}

public struct Capabilities: Equatable, Codable {
    public let vm: Bool
    public let container: Bool
    public let gpuInVm: Bool
    public let gpuInContainer: Bool
    /// The helper can cap and watch the GPU memory of a container. Helpers older than this feature do not say, which reads as false.
    public let gpuMemoryLimit: Bool
    /// The CPU models a VM can be given, `host` first. Helpers older than the CPU settings do not say, which reads as the host CPU only.
    public let cpuModels: [String]
    /// A VM can be given more than one socket. False for older helpers.
    public let cpuTopology: Bool
    /// The CPU flags a VM can have switched on or off (`nested-virt`, `aes`). None for older helpers.
    public let cpuFlags: [String]
    /// A container can get a hard cap on its CPU time. False for older helpers.
    public let cpuLimit: Bool
    /// The helper serves the console. Helpers older than this feature do not say, which reads as false (a Mac is still allowed by its OS, see TerminalSupport).
    public let terminal: Bool
    /// The helper can run sandboxes right now (Firecracker, /dev/kvm and a ready template). False for older helpers.
    public let sandbox: Bool

    public init(vm: Bool, container: Bool, gpuInVm: Bool, gpuInContainer: Bool, gpuMemoryLimit: Bool = false,
                cpuModels: [String] = CpuSettings.defaultModels, cpuTopology: Bool = false, cpuFlags: [String] = [], cpuLimit: Bool = false, terminal: Bool = false,
                sandbox: Bool = false) {
        self.vm = vm
        self.container = container
        self.gpuInVm = gpuInVm
        self.gpuInContainer = gpuInContainer
        self.gpuMemoryLimit = gpuMemoryLimit
        self.cpuModels = cpuModels
        self.cpuTopology = cpuTopology
        self.cpuFlags = cpuFlags
        self.cpuLimit = cpuLimit
        self.terminal = terminal
        self.sandbox = sandbox
    }

    enum CodingKeys: String, CodingKey { case vm, container, gpuInVm, gpuInContainer, gpuMemoryLimit, cpuModels, cpuTopology, cpuFlags, cpuLimit, terminal, sandbox }

    /// Capabilities saved before a feature leave out its fields: no `gpuMemoryLimit`, no CPU settings.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(vm: try box.decode(Bool.self, forKey: .vm), container: try box.decode(Bool.self, forKey: .container),
                  gpuInVm: try box.decode(Bool.self, forKey: .gpuInVm), gpuInContainer: try box.decode(Bool.self, forKey: .gpuInContainer),
                  gpuMemoryLimit: try box.decodeIfPresent(Bool.self, forKey: .gpuMemoryLimit) ?? false,
                  cpuModels: try box.decodeIfPresent([String].self, forKey: .cpuModels) ?? CpuSettings.defaultModels,
                  cpuTopology: try box.decodeIfPresent(Bool.self, forKey: .cpuTopology) ?? false,
                  cpuFlags: try box.decodeIfPresent([String].self, forKey: .cpuFlags) ?? [],
                  cpuLimit: try box.decodeIfPresent(Bool.self, forKey: .cpuLimit) ?? false,
                  terminal: try box.decodeIfPresent(Bool.self, forKey: .terminal) ?? false,
                  sandbox: try box.decodeIfPresent(Bool.self, forKey: .sandbox) ?? false)
    }
}

public struct FactsReport: Equatable {
    public let os: String
    public let arch: String
    public let cpuCores: Int
    public let ramTotalMb: Int
    public let diskTotalGb: Int
    public let freeRamMb: Int
    public let freeDiskGb: Int
    public let gpu: [GpuInfo]
    public let capabilities: Capabilities
    public let problems: [HostProblem]
    /// Which helper program runs and which engine it uses. Helpers older than contract 1.3.0 do not say, so both can be nil.
    public let agentVersion: String?
    public let engine: EngineReport?
    /// The SHA-256 of the helper's own program file (see AgentBuild). Helpers that do not say it give nil.
    public let agentBuild: String?
    /// The CPU's name as the helper reported it, cleaned and cut to 120 characters (see CpuModelText). Helpers that do not say it give nil.
    public let cpuModel: String?
    /// What the helper can offer for sandboxes. Only kept from a helper that says `capabilities.sandbox`; nil otherwise.
    public let sandbox: SandboxFacts?

    static let keys: Set<String> = ["os", "arch", "cpu_cores", "cpu_model", "ram_total_mb", "disk_total_gb", "free_ram_mb", "free_disk_gb", "gpu", "capabilities", "problems", "agent_version", "engine", "agent_build", "sandbox"]
    static let maxGpus = 16
    static let maxProblems = 20
    private static let codePattern = #/^[a-z0-9_]{1,64}$/#

    init(_ object: StrictObject) throws {
        os = try object.choice("os", among: ["macos", "linux", "windows"])
        arch = try object.choice("arch", among: ["arm64", "aarch64", "x86_64"])
        cpuCores = try object.int("cpu_cores", range: 1...100_000)
        cpuModel = try CpuModelText.optional(object, "cpu_model")
        ramTotalMb = try object.int("ram_total_mb", range: 1...100_000_000)
        diskTotalGb = try object.int("disk_total_gb", range: 1...100_000_000)
        freeRamMb = try object.int("free_ram_mb", range: 0...100_000_000)
        freeDiskGb = try object.int("free_disk_gb", range: 0...100_000_000)
        gpu = try object.objects("gpu", allowed: ["vendor", "model", "memory_mb"], maxCount: Self.maxGpus).map(Self.gpuInfo)
        let caps = try object.object("capabilities", allowed: ["vm", "container", "gpu_in_vm", "gpu_in_container", "gpu_memory_limit", "terminal",
                                                               "cpu_models", "cpu_topology", "cpu_flags", "cpu_limit", "sandbox"])
        capabilities = Capabilities(vm: try caps.bool("vm"), container: try caps.bool("container"),
                                    gpuInVm: try caps.bool("gpu_in_vm"), gpuInContainer: try caps.bool("gpu_in_container"),
                                    gpuMemoryLimit: caps.has("gpu_memory_limit") ? try caps.bool("gpu_memory_limit") : false,
                                    cpuModels: caps.has("cpu_models") ? try CpuSettings.offeredModels(caps) : CpuSettings.defaultModels,
                                    cpuTopology: caps.has("cpu_topology") ? try caps.bool("cpu_topology") : false,
                                    cpuFlags: caps.has("cpu_flags") ? try CpuSettings.offeredFlags(caps) : [],
                                    cpuLimit: caps.has("cpu_limit") ? try caps.bool("cpu_limit") : false,
                                    terminal: caps.has("terminal") ? try caps.bool("terminal") : false,
                                    sandbox: caps.has("sandbox") ? try caps.bool("sandbox") : false)
        problems = object.has("problems") ? try object.objects("problems", allowed: ["code", "message", "fix"], maxCount: Self.maxProblems).map(Self.problem) : []
        agentVersion = try ReportedVersion.optional(object, "agent_version")
        engine = object.has("engine") ? try EngineReport(try object.object("engine", allowed: EngineReport.keys)) : nil
        agentBuild = try AgentBuild.optional(object, "agent_build")
        let sandboxFacts = object.has("sandbox") ? try SandboxFacts(object.object("sandbox", allowed: SandboxFacts.keys)) : nil
        sandbox = capabilities.sandbox ? sandboxFacts : nil
    }

    private static func problem(_ item: StrictObject) throws -> HostProblem {
        HostProblem(code: try item.string("code", pattern: codePattern, maxLength: 64, minLength: 1), message: try item.string("message", maxLength: 300, minLength: 1),
                    fix: try item.string("fix", maxLength: 500))
    }

    private static func gpuInfo(_ item: StrictObject) throws -> GpuInfo {
        GpuInfo(vendor: try item.string("vendor", maxLength: 100), model: try item.string("model", maxLength: 200),
                memoryMb: item.has("memory_mb") ? try item.int("memory_mb", range: 0...100_000_000) : nil)
    }
}

public struct WorkloadReport: Equatable {
    public let id: String
    public let name: String
    public let kind: String
    public let state: String
    public let cpu: Int
    public let ramMb: Int
    public let diskGb: Int
    public let gpuMode: String
    public let address: String?
    public let bundleVersion: String?
    /// Only kept for a workload that is stopped or failed; a running one has no reason.
    public let stoppedReason: StoppedReasonReport?
    /// How the VM came up: "systemd", or "plain" (no systemd). Nil when the helper does not say.
    public let initMode: String?
    /// The GPU memory limit the helper says this container has, when it has one.
    public let gpuMemoryGb: Int?

    static let keys: Set<String> = ["id", "name", "kind", "state", "cpu", "ram_mb", "disk_gb", "gpu_mode", "address", "bundle_version", "stopped_reason", "init_mode", "gpu_memory_gb"]
    static let statesWithAReason: Set<String> = ["stopped", "failed"]
    static let maxPerMachine = 1000

    init(_ object: StrictObject) throws {
        id = try object.id("id")
        name = try object.id("name")
        kind = try object.choice("kind", among: ["vm", "container"])
        state = try object.choice("state", among: ["provisioning", "running", "stopped", "failed", "deleting"])
        cpu = try object.int("cpu", range: 1...100_000)
        ramMb = try object.int("ram_mb", range: 1...100_000_000)
        diskGb = try object.int("disk_gb", range: 1...100_000_000)
        gpuMode = try object.choice("gpu_mode", among: ["none", "container", "passthrough"])
        address = try object.optionalString("address", maxLength: 255)
        bundleVersion = try Self.version(object)
        let reason = object.has("stopped_reason") ? try StoppedReasonReport(object.object("stopped_reason", allowed: StoppedReasonReport.keys)) : nil
        stoppedReason = Self.statesWithAReason.contains(state) ? reason : nil
        initMode = object.has("init_mode") ? try object.choice("init_mode", among: ["systemd", "plain"]) : nil
        gpuMemoryGb = object.has("gpu_memory_gb") ? try object.int("gpu_memory_gb", range: GpuBooking.allowedGb) : nil
    }

    private static func version(_ object: StrictObject) throws -> String? {
        guard let text = try object.optionalString("bundle_version", maxLength: 32) else { return nil }
        guard Ids.isSemver(text) else { throw InputError("bundle_version must look like 1.2.3") }
        return text
    }
}

public struct HeartbeatRequest: Equatable {
    public let facts: FactsReport
    public let workloads: [WorkloadReport]
    public let bundleVersion: String?
    /// Where the Root can reach this Agent's API, when the Agent says so.
    public let agentPort: Int?

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["facts", "workloads", "bundle_version", "agent_port"])
        agentPort = object.has("agent_port") ? try object.int("agent_port", range: 1...65535) : nil
        facts = try FactsReport(try object.object("facts", allowed: FactsReport.keys))
        workloads = try object.objects("workloads", allowed: WorkloadReport.keys, maxCount: WorkloadReport.maxPerMachine).map(WorkloadReport.init)
        bundleVersion = try Self.version(object)
    }

    private static func version(_ object: StrictObject) throws -> String? {
        guard let text = try object.optionalString("bundle_version", maxLength: 32) else { return nil }
        guard Ids.isSemver(text) else { throw InputError("bundle_version must look like 1.2.3") }
        return text
    }
}

public struct CreateEnrollmentRequest: Equatable {
    public let name: String
    /// When set, only a machine connecting from this address can use the token.
    public let expectedIp: String?

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["name", "ip"])
        name = try object.id("name")
        expectedIp = try object.optionalString("ip", maxLength: 15)
        guard expectedIp == nil || IPv4.isValid(expectedIp!) else { throw InputError("ip is not a valid IPv4 address") }
    }
}

public struct AddScanItem: Equatable {
    public let resultId: Int
    public let name: String
}

/// "Add these found devices": each becomes an enrollment token pinned to the address that was found.
public struct AddScanRequest: Equatable {
    public static let maxItems = 50
    public let items: [AddScanItem]

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["items"])
        let list = try object.objects("items", allowed: ["result_id", "name"], maxCount: Self.maxItems)
        guard !list.isEmpty else { throw InputError("pick at least one device") }
        items = try list.map { AddScanItem(resultId: try $0.int("result_id", range: 1...Int(Int32.max)), name: try $0.id("name")) }
        guard Set(items.map(\.name)).count == items.count, Set(items.map(\.resultId)).count == items.count else { throw InputError("names and devices must be different from each other") }
    }
}

/// An operator asking for a workload. Placement decides the machine unless one is named.
public struct CreateWorkloadOperatorRequest: Equatable {
    public let name: String
    public let kind: String
    public let cpu: Int
    public let ramMb: Int
    public let diskGb: Int
    public let gpuMode: String
    public let machine: String?
    /// The catalog id of the image to start from. Blank when the request does not say. The browser never names an engine image: only this id, and the parent maps it.
    public let bundle: String
    /// The GPU memory this container may use, in GB. Nil: the whole card is shared, nothing is booked.
    public let gpuMemoryGb: Int?
    /// How many sockets the VM's CPUs are spread over. Nil: one, as before.
    public let cpuSockets: Int?
    /// The CPU model the VM sees, one its machine lists. Nil: `host`, the machine's own CPU.
    public let cpuType: String?
    /// CPU flags switched `on` or `off` for the VM, by name. Nil: what the CPU type gives.
    public let cpuFlags: [String: String]?
    /// A hard cap on the container's CPU time, in percent of one core. Nil: no cap.
    public let cpuLimitPercent: Int?

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["name", "kind", "cpu", "ram_mb", "disk_gb", "gpu_mode", "machine", "bundle", "gpu_memory_gb",
                                                            "cpu_sockets", "cpu_type", "cpu_flags", "cpu_limit_percent"])
        name = try object.id("name")
        kind = try object.choice("kind", among: ["vm", "container"])
        cpu = try object.int("cpu", range: 1...64)
        ramMb = try object.int("ram_mb", range: 512...1_048_576)
        diskGb = try object.int("disk_gb", range: 1...100_000)
        gpuMode = object.has("gpu_mode") ? try object.choice("gpu_mode", among: ["none", "container", "passthrough"]) : "none"
        machine = object.has("machine") ? try object.id("machine") : nil
        bundle = object.has("bundle") ? try Self.knownBundle(object) : ImageCatalog.blankId
        gpuMemoryGb = object.has("gpu_memory_gb") ? try object.int("gpu_memory_gb", range: GpuBooking.allowedGb) : nil
        guard gpuMemoryGb == nil || gpuMode == "container" else { throw InputError("gpu_memory_gb can only be set when gpu_mode is container") }
        cpuSockets = try CpuSettings.sockets(object, kind: kind, cpu: cpu)
        cpuType = try CpuSettings.type(object, kind: kind)
        cpuFlags = try CpuSettings.flags(object, kind: kind)
        cpuLimitPercent = try CpuSettings.limitPercent(object, kind: kind, cpu: cpu)
    }

    /// The same wish, pinned to the machine the parent chose for it.
    public func placed(on machine: String) -> CreateWorkloadOperatorRequest {
        CreateWorkloadOperatorRequest(name: name, kind: kind, cpu: cpu, ramMb: ramMb, diskGb: diskGb, gpuMode: gpuMode, machine: machine, bundle: bundle, gpuMemoryGb: gpuMemoryGb,
                                      cpuSockets: cpuSockets, cpuType: cpuType, cpuFlags: cpuFlags, cpuLimitPercent: cpuLimitPercent)
    }

    public init(name: String, kind: String, cpu: Int, ramMb: Int, diskGb: Int, gpuMode: String, machine: String?, bundle: String, gpuMemoryGb: Int? = nil,
                cpuSockets: Int? = nil, cpuType: String? = nil, cpuFlags: [String: String]? = nil, cpuLimitPercent: Int? = nil) {
        self.gpuMemoryGb = gpuMemoryGb
        self.cpuSockets = cpuSockets
        self.cpuType = cpuType
        self.cpuFlags = cpuFlags
        self.cpuLimitPercent = cpuLimitPercent
        self.name = name
        self.kind = kind
        self.cpu = cpu
        self.ramMb = ramMb
        self.diskGb = diskGb
        self.gpuMode = gpuMode
        self.machine = machine
        self.bundle = bundle
    }

    private static func knownBundle(_ object: StrictObject) throws -> String {
        let id = try object.string("bundle", pattern: ImageCatalog.pattern, maxLength: 32, minLength: 1)
        guard ImageCatalog.entry(id: id) != nil else { throw InputError("bundle is not one of the listed images") }
        return id
    }
}

/// Deleting asks for an explicit yes in the request body, so a stray call cannot do it.
public struct ConfirmRequest: Equatable {
    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["confirm"])
        guard try object.bool("confirm") else { throw InputError("confirm must be true") }
    }
}
