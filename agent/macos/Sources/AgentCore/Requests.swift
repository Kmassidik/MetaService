import Foundation
import MSCore

/// Bodies the Root sends, read strictly. Field names and limits follow contract/openapi.yaml.
public struct CreateWorkloadRequest: Equatable {
    public let commandId: String
    public let name: String
    public let kind: WorkloadKind
    public let cpu: Int
    public let ramMb: Int
    public let diskGb: Int
    public let gpuMode: GpuMode
    public let image: String?

    private static let imagePattern = #/^[a-z0-9][a-z0-9._:\/-]{0,127}$/#

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["command_id", "name", "kind", "cpu", "ram_mb", "disk_gb", "gpu_mode", "image"])
        commandId = try object.id("command_id")
        name = try object.id("name")
        kind = WorkloadKind(rawValue: try object.choice("kind", among: ["vm", "container"]))!
        cpu = try object.int("cpu", range: 1...64)
        ramMb = try object.int("ram_mb", range: 512...1_048_576)
        diskGb = try object.int("disk_gb", range: 1...100_000)
        gpuMode = object.has("gpu_mode") ? GpuMode(rawValue: try object.choice("gpu_mode", among: ["none", "container", "passthrough"]))! : .none
        image = object.has("image") ? try object.string("image", pattern: Self.imagePattern, maxLength: 128, minLength: 1) : nil
    }
}

public struct BundleInstallRequest: Equatable {
    public let commandId: String
    public let version: String
    public let sha256: String
    public let workloadId: String?

    private static let sha = #/^[0-9a-f]{64}$/#

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["command_id", "version", "sha256", "workload_id"])
        commandId = try object.id("command_id")
        let text = try object.string("version", maxLength: 32, minLength: 1)
        guard Ids.isSemver(text) else { throw InputError("version must look like 1.2.3") }
        version = text
        sha256 = try object.string("sha256", pattern: Self.sha, maxLength: 64, minLength: 64)
        workloadId = object.has("workload_id") ? try object.id("workload_id") : nil
    }
}
