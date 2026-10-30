import Foundation

/// The plain sentences a person reads in the panel and an AI reads in a reply. Pure.
public enum McpDescribe {
    /// What a stored action will do, with the exact size. `params` is what the request stored: machine, vm, name, size, vcpu, ram_mb, disk_gb, image, gpu_memory_gb.
    public static func action(kind: String, params: [String: Any]) -> String {
        switch kind {
        case "create": return create(params)
        case "delete": return "Delete \(vm(params)) for good"
        case "start": return "Start \(vm(params))"
        case "stop": return "Stop \(vm(params))"
        default: return "Do something unknown"
        }
    }

    private static func create(_ params: [String: Any]) -> String {
        let name = (params["name"] as? String).map { "a VM named \"\($0)\"" } ?? "a VM"
        let size = params["size"] as? String ?? "custom"
        let numbers = "\(params["vcpu"] as? Int ?? 0) CPU, \(params["ram_mb"] as? Int ?? 0) MB RAM, \(params["disk_gb"] as? Int ?? 0) GB disk"
        let place = (params["machine"] as? String).map { "on machine \($0)" } ?? "on the least loaded machine that fits"
        var text = "Create \(name) (size \(size): \(numbers)) \(place)"
        if let image = params["image"] as? String { text += ", image \(image)" }
        if let gpu = params["gpu_memory_gb"] as? Int { text += ", with a GPU memory limit of \(gpu) GB" }
        return text
    }

    private static func vm(_ params: [String: Any]) -> String {
        let id = params["vm"] as? String ?? "?"
        let name = (params["vm_name"] as? String).map { " (\"\($0)\")" } ?? ""
        return "the VM \(id)\(name) on machine \(params["machine"] as? String ?? "?")"
    }

    /// What an AI reads when a call waits for a person.
    public static let waitingForApproval = "A person must approve this in the panel (Settings, AI access)."

    /// Shown for a request in each final state that is not a success.
    public static func ending(_ state: String) -> String? {
        switch state {
        case "denied": return "A person denied this request in the panel. Do not try again unless the person asks."
        case "expired": return "Nobody approved this within 24 hours, so it was dropped. Ask again if it is still needed."
        default: return nil
        }
    }
}
