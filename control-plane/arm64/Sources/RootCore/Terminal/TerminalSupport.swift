/// Which machines can open a console. Only the macOS helper serves one for now; the Linux helper has none yet.
public enum TerminalSupport {
    public static let message = "The console is only available on Mac machines for now."

    public static func isSupported(machineOS: String) -> Bool {
        machineOS == "macos"
    }
}
