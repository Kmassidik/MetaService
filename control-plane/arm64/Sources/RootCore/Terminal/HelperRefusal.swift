/// What a helper's refusal of the console socket (its plain HTTP answer before any upgrade) means for the person, in the words of a closed console.
public enum HelperRefusal {
    public static let noAgentText = "this VM has no incus agent, so the console cannot open"
    public static let consoleOpenText = "this workload already has a console"

    /// `code` is the error code in the helper's answer; anything unknown is "the VM is not available".
    public static func reason(code: String?) -> CloseReason {
        switch code {
        case "not_running": return .vmStopped
        case "console_open": return CloseReason(code: CloseReason.internalCode, text: consoleOpenText)
        case "no_agent": return CloseReason(code: CloseReason.internalCode, text: noAgentText)
        default: return .vmUnavailable
        }
    }
}
