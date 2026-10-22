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

    static let keys: Set<String> = ["os", "arch", "cpu_cores", "ram_total_mb", "disk_total_gb", "free_ram_mb", "free_disk_gb", "gpu", "capabilities", "problems", "agent_version", "engine", "agent_build"]
    static let maxGpus = 16
    static let maxProblems = 20
    private static let codePattern = #/^[a-z0-9_]{1,64}$/#

    init(_ object: StrictObject) throws {
        os = try object.choice("os", among: ["macos", "linux", "windows"])
        arch = try object.choice("arch", among: ["arm64", "aarch64", "x86_64"])
        cpuCores = try object.int("cpu_cores", range: 1...100_000)
        ramTotalMb = try object.int("ram_total_mb", range: 1...100_000_000)
        diskTotalGb = try object.int("disk_total_gb", range: 1...100_000_000)
        freeRamMb = try object.int("free_ram_mb", range: 0...100_000_000)
        freeDiskGb = try object.int("free_disk_gb", range: 0...100_000_000)
        gpu = try object.objects("gpu", allowed: ["vendor", "model", "memory_mb"], maxCount: Self.maxGpus).map(Self.gpuInfo)
        let caps = try object.object("capabilities", allowed: ["vm", "container", "gpu_in_vm", "gpu_in_container"])
        capabilities = Capabilities(vm: try caps.bool("vm"), container: try caps.bool("container"),
                                    gpuInVm: try caps.bool("gpu_in_vm"), gpuInContainer: try caps.bool("gpu_in_container"))
        problems = object.has("problems") ? try object.objects("problems", allowed: ["code", "message", "fix"], maxCount: Self.maxProblems).map(Self.problem) : []
        agentVersion = try ReportedVersion.optional(object, "agent_version")
        engine = object.has("engine") ? try EngineReport(try object.object("engine", allowed: EngineReport.keys)) : nil
        agentBuild = try AgentBuild.optional(object, "agent_build")
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

    static let keys: Set<String> = ["id", "name", "kind", "state", "cpu", "ram_mb", "disk_gb", "gpu_mode", "address", "bundle_version", "stopped_reason", "init_mode"]
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

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["name", "kind", "cpu", "ram_mb", "disk_gb", "gpu_mode", "machine", "bundle"])
        name = try object.id("name")
        kind = try object.choice("kind", among: ["vm", "container"])
        cpu = try object.int("cpu", range: 1...64)
        ramMb = try object.int("ram_mb", range: 512...1_048_576)
        diskGb = try object.int("disk_gb", range: 1...100_000)
        gpuMode = object.has("gpu_mode") ? try object.choice("gpu_mode", among: ["none", "container", "passthrough"]) : "none"
        machine = object.has("machine") ? try object.id("machine") : nil
        bundle = object.has("bundle") ? try Self.knownBundle(object) : ImageCatalog.blankId
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
