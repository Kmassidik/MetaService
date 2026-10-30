import Foundation

/// What each tool's `arguments` say, read strictly: unknown fields, wrong types and numbers out of range are refused with a sentence that names the field.
/// The same field lists are in `McpToolSchemas`, so what the AI is told is what is accepted.
public struct McpCreateVmInput: Equatable {
    public static let defaultWaitSeconds = 30
    public static let waitSeconds = 0...60
    static let keyPattern = #/^[A-Za-z0-9_.:-]{1,64}$/#
    static let imagePattern = #/^[a-z0-9][a-z0-9-]{0,31}$/#
    static let maxPublicKeyCharacters = 2048
    static let fields: Set<String> = ["machine", "name", "size", "vcpu", "ram_mb", "disk_gb", "image", "gpu_memory_gb", "ssh_public_key", "idempotency_key", "wait_seconds"]

    public let machine: String?
    public let name: String?
    public let size: McpSize
    public let dimensions: McpSize.Dimensions
    public let image: String?
    public let gpuMemoryGb: Int?
    public let sshPublicKey: String?
    public let idempotencyKey: String?
    public let waitSeconds: Int

    public init(arguments: Data) throws {
        let object = try StrictObject(data: arguments, allowed: Self.fields)
        machine = object.has("machine") ? try object.id("machine") : nil
        name = object.has("name") ? try object.id("name") : nil
        guard object.has("size") else { throw InputError("size is required: small, medium, large or custom") }
        size = try McpSize(rawValue: object.choice("size", among: Set(McpSize.allCases.map(\.rawValue)))) ?? .small
        dimensions = try Self.dimensions(of: size, object)
        image = object.has("image") ? try object.string("image", pattern: Self.imagePattern, maxLength: 32, minLength: 1) : nil
        gpuMemoryGb = object.has("gpu_memory_gb") ? try object.int("gpu_memory_gb", range: 1...1024) : nil
        sshPublicKey = object.has("ssh_public_key") ? try object.string("ssh_public_key", maxLength: Self.maxPublicKeyCharacters, minLength: 1) : nil
        idempotencyKey = object.has("idempotency_key") ? try object.string("idempotency_key", pattern: Self.keyPattern, maxLength: 64, minLength: 1) : nil
        waitSeconds = object.has("wait_seconds") ? try object.int("wait_seconds", range: Self.waitSeconds) : Self.defaultWaitSeconds
    }

    /// A preset takes its numbers from the preset and refuses the number fields; custom needs all three.
    private static func dimensions(of size: McpSize, _ object: StrictObject) throws -> McpSize.Dimensions {
        let named = ["vcpu", "ram_mb", "disk_gb"].filter(object.has)
        if let preset = size.preset {
            guard named.isEmpty else { throw InputError("vcpu, ram_mb and disk_gb are only for size custom: size \(size.rawValue) is \(preset.vcpu) CPU, \(preset.ramMb) MB, \(preset.diskGb) GB") }
            return preset
        }
        guard named.count == 3 else { throw InputError("size custom needs vcpu, ram_mb and disk_gb") }
        return McpSize.Dimensions(vcpu: try object.int("vcpu", range: McpSize.customVcpu), ramMb: try object.int("ram_mb", range: McpSize.customRamMb),
                                  diskGb: try object.int("disk_gb", range: McpSize.customDiskGb))
    }
}

/// start_vm and stop_vm take a wait; delete_vm and vm_status do not. `wait` is nil for the tools that do not have one.
public struct McpVmInput: Equatable {
    public let machine: String
    public let vm: String
    public let waitSeconds: Int

    public init(arguments: Data, withWait: Bool) throws {
        let object = try StrictObject(data: arguments, allowed: withWait ? ["machine", "vm", "wait_seconds"] : ["machine", "vm"])
        guard object.has("machine"), object.has("vm") else { throw InputError("machine and vm are required") }
        machine = try object.id("machine")
        vm = try object.id("vm")
        waitSeconds = withWait && object.has("wait_seconds") ? try object.int("wait_seconds", range: McpCreateVmInput.waitSeconds) : McpCreateVmInput.defaultWaitSeconds
    }
}

/// machine_capacity (machine required), list_vms (machine optional) and get_request (request_id required).
public struct McpLookupInput: Equatable {
    public let machine: String?
    public let requestId: String?

    public static func capacity(arguments: Data) throws -> McpLookupInput {
        let object = try StrictObject(data: arguments, allowed: ["machine"])
        guard object.has("machine") else { throw InputError("machine is required") }
        return McpLookupInput(machine: try object.id("machine"), requestId: nil)
    }

    public static func vms(arguments: Data) throws -> McpLookupInput {
        let object = try StrictObject(data: arguments, allowed: ["machine"])
        return McpLookupInput(machine: object.has("machine") ? try object.id("machine") : nil, requestId: nil)
    }

    public static func request(arguments: Data) throws -> McpLookupInput {
        let object = try StrictObject(data: arguments, allowed: ["request_id"])
        guard object.has("request_id") else { throw InputError("request_id is required") }
        return McpLookupInput(machine: nil, requestId: try object.id("request_id"))
    }

    /// list_machines takes no arguments at all.
    public static func none(arguments: Data) throws {
        _ = try StrictObject(data: arguments, allowed: [])
    }
}
