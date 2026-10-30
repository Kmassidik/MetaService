import Foundation
import RootCore

/// The create a request stored, read back when it runs: straight away, or after a person approved it. Only what a create needs; sizes are always numbers here.
struct McpStoredCreate {
    let machine: String?
    let name: String?
    let size: McpSize
    let dimensions: McpSize.Dimensions
    let image: String?
    let gpuMemoryGb: Int?

    init(input: McpCreateVmInput) {
        machine = input.machine
        name = input.name
        size = input.size
        dimensions = input.dimensions
        image = input.image
        gpuMemoryGb = input.gpuMemoryGb
    }

    init?(stored params: [String: Any]) {
        guard let size = (params["size"] as? String).flatMap(McpSize.init(rawValue:)), let vcpu = params["vcpu"] as? Int,
              let ram = params["ram_mb"] as? Int, let disk = params["disk_gb"] as? Int else { return nil }
        self.size = size
        dimensions = McpSize.Dimensions(vcpu: vcpu, ramMb: ram, diskGb: disk)
        machine = params["machine"] as? String
        name = params["name"] as? String
        image = params["image"] as? String
        gpuMemoryGb = params["gpu_memory_gb"] as? Int
    }

    var wish: McpWish { McpWish(vcpu: dimensions.vcpu, ramMb: dimensions.ramMb, diskGb: dimensions.diskGb, gpuMemoryGb: gpuMemoryGb) }

    /// The stored form. The public key is added by the caller, and removed again once the VM has it.
    var params: [String: Any] {
        var params: [String: Any] = ["size": size.rawValue, "vcpu": dimensions.vcpu, "ram_mb": dimensions.ramMb, "disk_gb": dimensions.diskGb]
        params["machine"] = machine
        params["name"] = name
        params["image"] = image
        params["gpu_memory_gb"] = gpuMemoryGb
        return params
    }
}
