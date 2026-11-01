import Foundation

/// The helper's own `autostart on` verb, as the install and the update call it: after the helper has started and answered, so a machine that cannot register itself for the
/// next restart is still a working machine. The verb needs no root; it writes a systemd user unit (Linux) or a LaunchAgent (Mac) in the login's home.
///
/// Its exit code is the whole answer: 0 is fully in place, 3 is "written, one step for the owner" (a `sudo loginctl enable-linger` on Linux, automatic login on a Mac), and
/// anything else is a failure that is told plainly and never stops the install or the update. The sentences below are fixed text: nothing the other computer printed
/// reaches the panel, and the helper's own words go to `logs/agent.log` there.
public enum HelperAutostart {
    public static let exitNeedsOwner = 3
    static let exitMarker = "ms-autostart-exit:"
    static let systemMarker = "ms-autostart-system:"
    private static let macSystemName = "Darwin"
    static let verb = "autostart on"
    static let program = "./bin/" + InstallPlan.programName

    public enum Result: Equatable {
        case effective
        case needsOwner
        case failed
    }

    // MARK: the install

    /// Run on the other computer after the helper answered. It always ends with the exit marker, whatever the verb did.
    public static func installScript(box: String) -> String {
        "cd \(Shell.quote(box)) && \(program) \(verb) --box \(Shell.quote(box)) >> logs/agent.log 2>&1; echo \"\(exitMarker) $?\"; echo \"\(systemMarker) $(uname -s)\"\n"
    }

    /// Whether the computer said it is a Mac (`uname -s` is Darwin); anything else is read as Linux.
    public static func isMac(output: String) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { $0.hasPrefix(systemMarker) && $0.hasSuffix(macSystemName) }
    }

    /// The last marker of the output; a missing or odd one is a failure.
    public static func result(output: String) -> Result {
        let marked = output.split(whereSeparator: \.isNewline).filter { $0.hasPrefix(exitMarker) }
        guard let code = marked.last.flatMap({ Int($0.dropFirst(exitMarker.count).trimmingCharacters(in: .whitespaces)) }) else { return .failed }
        switch code {
        case 0: return .effective
        case exitNeedsOwner: return .needsOwner
        default: return .failed
        }
    }

    public static func installSentence(_ result: Result, isMac: Bool, login: String) -> String {
        switch result {
        case .effective: return "It starts again by itself after a restart of that computer."
        case .needsOwner: return "Installed. One step is left for the owner so it starts again after a restart: " + ownerStep(isMac: isMac, login: login)
        case .failed: return "It could not be set to start again by itself after a restart (the reason is in logs/agent.log in the box); after a restart, run start.sh in the box."
        }
    }

    /// The one thing the owner does, in plain words. The login is shown only when it is a plain name, never anything else.
    public static func ownerStep(isMac: Bool, login: String) -> String {
        guard !isMac else { return "turn on automatic login for this user on the Mac (System Settings, Users & Groups)." }
        let name = AutostartScript.isPlainLogin(login) ? login : "<login>"
        return "run `sudo loginctl enable-linger \(name)` once on that computer."
    }

    // MARK: the update

    /// Lines for the update script: run for the NEW program once it answered, and end with one of the codes below. A failure is logged and never fails the update.
    static let updateLines = """
    ./bin/metaservice-agent \(verb) --box "$box" >> logs/agent.log 2>&1; rc=$?
          [ "$rc" != 0 ] || say updated
          [ "$rc" != \(exitNeedsOwner) ] || [ "$(uname -s)" != Darwin ] || say updated_autologin
          [ "$rc" != \(exitNeedsOwner) ] || say updated_linger
          say updated_no_autostart
    """
}
