/// Which machines can open a console: a helper that says it serves one (`terminal` in its capabilities), or a Mac,
/// because Mac helpers older than the flag already serve it. A Linux helper without the flag has to be updated first.
public enum TerminalSupport {
    public static let message = "Update the helper on this machine to use the terminal."
    private static let macOS = "macos"

    public static func isSupported(machineOS: String, capabilities: Capabilities?) -> Bool {
        capabilities?.terminal == true || machineOS == macOS
    }
}
