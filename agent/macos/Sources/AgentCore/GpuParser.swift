import Foundation

/// Reads `system_profiler SPDisplaysDataType -json` into the list of GPUs.
public enum GpuParser {
    private static let maxGpus = 16
    private static let vendors = ["sppci_vendor_apple": "apple", "sppci_vendor_nvidia": "nvidia", "sppci_vendor_amd": "amd", "sppci_vendor_intel": "intel"]

    public static func parse(_ json: Data) -> [Gpu] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any], let list = root["SPDisplaysDataType"] as? [[String: Any]] else { return [] }
        return list.prefix(maxGpus).compactMap { item in
            guard let model = item["sppci_model"] as? String, !model.isEmpty else { return nil }
            let raw = item["spdisplays_vendor"] as? String ?? item["sppci_vendor"] as? String ?? ""
            return Gpu(vendor: vendors[raw] ?? clean(raw), model: String(model.prefix(200)), memoryMb: memory(item["spdisplays_vram"] as? String))
        }
    }

    private static func clean(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: "sppci_vendor_", with: "")
        return text.isEmpty ? "unknown" : String(text.prefix(100))
    }

    /// "8 GB" or "1536 MB" to megabytes; anything else is nil (Apple silicon shares system memory).
    private static func memory(_ text: String?) -> Int? {
        guard let parts = text?.split(separator: " "), parts.count == 2, let amount = Int(parts[0]) else { return nil }
        switch parts[1].uppercased() {
        case "GB": return amount * 1024
        case "MB": return amount
        default: return nil
        }
    }
}
