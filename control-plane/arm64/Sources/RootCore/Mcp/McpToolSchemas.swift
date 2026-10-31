import Foundation

/// The JSON Schema of each tool's input, as `tools/list` sends it. Every schema is an object with `additionalProperties: false`.
public enum McpToolSchemas {
    private static func text(_ description: String, pattern: String? = nil, maxLength: Int? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "string", "description": description]
        schema["pattern"] = pattern
        schema["maxLength"] = maxLength
        return schema
    }

    private static func number(_ description: String, _ range: ClosedRange<Int>, default value: Int? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "integer", "description": description, "minimum": range.lowerBound, "maximum": range.upperBound]
        schema["default"] = value
        return schema
    }

    private static func object(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }

    private static let idPattern = "^[a-z0-9][a-z0-9-]{0,62}$"
    private static let machine = text("The machine id from list_machines.", pattern: idPattern, maxLength: 63)
    private static let vm = text("The VM id from list_vms or create_vm.", pattern: idPattern, maxLength: 63)
    private static let wait = number("How many seconds to wait for the VM to be running before answering with a request_id to poll.", McpCreateVmInput.waitSeconds, default: McpCreateVmInput.defaultWaitSeconds)

    public static func input(of tool: McpTool) -> [String: Any] {
        switch tool {
        case .listMachines: return object([:])
        case .machineCapacity: return object(["machine": machine], required: ["machine"])
        case .listVms: return object(["machine": text("Only the VMs on this machine id.", pattern: idPattern, maxLength: 63)])
        case .vmStatus, .deleteVm: return object(["machine": machine, "vm": vm], required: ["machine", "vm"])
        case .startVm, .stopVm: return object(["machine": machine, "vm": vm, "wait_seconds": wait], required: ["machine", "vm"])
        case .getRequest: return object(["request_id": text("The request_id an earlier call answered with.", pattern: idPattern, maxLength: 63)], required: ["request_id"])
        case .createVm: return createVm
        }
    }

    private static let createVm = object([
        "machine": text("The machine id from list_machines. Leave it out to use the least loaded machine that fits.", pattern: idPattern, maxLength: 63),
        "name": text("A name for the VM: lower case letters, digits and dashes. Leave it out for a generated one.", pattern: idPattern, maxLength: 63),
        "size": ["type": "string", "enum": McpSize.allCases.map(\.rawValue), "description": "small is 1 CPU, 2 GB RAM, 20 GB disk; medium 2, 4, 40; large 4, 8, 60; custom takes vcpu, ram_mb and disk_gb."],
        "vcpu": number("CPU cores. Only with size custom.", McpSize.customVcpu),
        "ram_mb": number("Memory in MB. Only with size custom.", McpSize.customRamMb),
        "disk_gb": number("Disk in GB. Only with size custom.", McpSize.customDiskGb),
        "image": text("An image id from the panel's image list. Leave it out for the default.", pattern: "^[a-z0-9][a-z0-9-]{0,31}$", maxLength: 32),
        "gpu_memory_gb": number("A GPU memory limit in GB. Needs the gpu scope.", 1...1024),
        "ssh_public_key": text("A public SSH key (one line) that may log in to the VM. Never a private key.", maxLength: McpCreateVmInput.maxPublicKeyCharacters),
        "idempotency_key": text("Any text you choose. Calling again with the same key returns the same VM instead of making a second one.", pattern: "^[A-Za-z0-9_.:-]{1,64}$", maxLength: 64),
        "wait_seconds": wait,
    ], required: ["size"])
}
