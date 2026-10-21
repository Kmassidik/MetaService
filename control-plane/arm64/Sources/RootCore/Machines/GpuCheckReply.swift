import Foundation

/// The answer to "is the GPU visible inside this container": what a helper found, cut to the contract's limits. The text comes from a helper, and the `detail` from inside the workload
/// itself, so all of it is untrusted: control characters go, long text is cut, and anything that is not the contract's shape is refused.
public struct GpuCheckReply: Encodable, Equatable, Sendable {
    public let gpuVisible: Bool
    public let how: String
    public let detail: String
    public let note: String

    public static let hows: Set<String> = ["nvidia-smi", "device nodes", "none"]
    public static let longestDetail = 1500
    public static let longestNote = 300
    public static let notGivenNote = "No GPU was given to this one."

    /// What a VM, or a container that was not given the GPU, answers without anyone looking inside.
    public static let notGiven = GpuCheckReply(gpuVisible: false, how: "none", detail: "", note: notGivenNote)

    /// True when this workload can have the GPU inside it at all: a container that was given the machine's GPU.
    public static func canHaveGpu(kind: String, gpuMode: String) -> Bool {
        kind == "container" && gpuMode == "container"
    }

    /// Reads a helper's JSON answer. Nil when it is not exactly the contract's shape.
    public static func parse(_ json: [String: Any]?) -> GpuCheckReply? {
        guard let json, Set(json.keys) == ["gpu_visible", "how", "detail", "note"],
              let visible = json["gpu_visible"] as? Bool, let how = json["how"] as? String, hows.contains(how),
              let detail = json["detail"] as? String, let note = json["note"] as? String else { return nil }
        let plainNote = printable(note, limit: longestNote)
        guard !plainNote.isEmpty else { return nil }
        return GpuCheckReply(gpuVisible: visible, how: how, detail: printable(detail, limit: longestDetail), note: plainNote)
    }

    /// The C0 controls (below the space) and the C1 controls, and DEL: none of them is text.
    private static let controls: Set<UInt32> = Set(0..<32).union(0x80...0x9f)
    private static let delete: UInt32 = 127

    /// Printable characters only (a new line stays a new line), cut to `limit`.
    static func printable(_ text: String, limit: Int) -> String {
        let kept = text.unicodeScalars.filter { $0 == "\n" || (!controls.contains($0.value) && $0.value != delete) }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit).description
    }
}
