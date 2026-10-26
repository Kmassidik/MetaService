import Foundation

/// The part of "Install it for me" that registers a helper which is already installed with the system's own boot service: a LaunchAgent of the login on a Mac, a
/// systemd unit on Linux. Nothing about the helper changes: both run `<box>/bin/metaservice-agent` with the flags `start.sh` writes, as the login user, from the box.
///
/// Without it a restart leaves that machine offline until somebody runs `~/metaservice-box/start.sh`, so the parent is green while its machines are grey
/// (seen on 2026-10-26, after two power cycles). The script is fixed text: the only things in it are the login user and the box of that computer, both read by
/// the check, never sent by the browser.
///
/// On a Mac it is a LaunchAgent of the login, in that login's own `gui/<uid>` domain, and never a LaunchDaemon of the system: Apple's container service belongs to
/// one login, so a helper of the system domain finds it stopped and `container system start` run there does nothing at all (measured on 2026-10-26). A LaunchAgent
/// needs that login to be signed in, which is why the Macs enable automatic login at boot — that setting is the operator's, not this script's. Do not move it back
/// to `/Library/LaunchDaemons`: there it survived a reboot and broke every Apple container.
enum AutostartScript {
    static let label = "io.metaservice.agent"
    /// Where a LaunchAgent of a login lives, under its home folder. `$HOME` is the home of whoever runs the line: the check and the removal run as that login,
    /// the install script builds the same path from the login itself.
    static let agentFolder = "Library/LaunchAgents"
    static let macPath = "$HOME/" + agentFolder + "/" + label + ".plist"
    /// The two jobs of the design that ran this helper from the system domain, taken away wherever they are found so an upgraded Mac ends up with one helper.
    static let legacyDaemonPath = "/Library/LaunchDaemons/" + label + ".plist"
    static let legacyContainerStartLabel = "io.metaservice.container-start"
    static let legacyContainerStartPath = "/Library/LaunchDaemons/" + legacyContainerStartLabel + ".plist"
    static let unitName = "metaservice-agent"
    static let linuxPath = "/etc/systemd/system/" + unitName + ".service"

    /// launchd restarts a job no sooner than this, so a program that fails at once cannot fill the disk with its own log.
    static let throttleSeconds = 10
    static let restartSeconds = 5
    /// The process stops on SIGTERM; the port has to be free before the service takes its place.
    private static let stopWaitSeconds = 2
    private static let stateFolder = "state"
    private static let logFile = "logs/agent.log"
    private static let macEngine = "apple"
    private static let linuxEngine = "incus"
    private static let plistEnd = "__METASERVICE_PLIST__"
    private static let unitEnd = "__METASERVICE_UNIT__"

    /// The whole sudo script for this part: it is not a package install, so it carries its own markers and asks the computer which system it is instead of
    /// being told. `aptget` and the apt log of the other parts have no meaning here.
    static func script(box: String, user: String) -> String {
        guard isPlainLogin(user) else { return refusal }
        let lines = ["echo \(InstallMissingScripts.okMarker)",
                     "[ \"$(id -u)\" = 0 ] || { echo '\(InstallMissingScripts.errorMarker) sudo did not give administrator rights'; exit 1; }",
                     "box=\(Shell.quote(box))",
                     "fail() { echo \"\(InstallMissingScripts.errorMarker) $1\"; exit 1; }",
                     "[ -d \"$box\" ] || fail \"there is no MetaService folder at $box on this computer, so there is nothing to register\"",
                     "if [ -x \"$box/stop.sh\" ]; then sh \"$box/stop.sh\" >/dev/null 2>&1 || true; fi",
                     "sleep \(stopWaitSeconds)",
                     "if [ \"$(uname -s)\" = Darwin ]; then"]
            + mac(box: box, user: user) + ["else"] + linux(box: box, user: user) + ["fi", "echo \(InstallMissingScripts.doneMarker)", ""]
        return lines.joined(separator: "\n")
    }

    private static let refusal = """
    echo \(InstallMissingScripts.okMarker)
    echo '\(InstallMissingScripts.errorMarker) this login'"'"'s name is not one MetaService writes a boot service for, so nothing was written'
    exit 1

    """

    // MARK: macOS

    /// The LaunchAgent of the login, and the jobs of the earlier design that must go first. The whole script is one `sudo sh -c`, so this half already runs as
    /// root: it writes the file into the login's own folder, gives it to that login, and loads it into that login's GUI domain — no `sudo` of its own, and no
    /// `UserName`, because a LaunchAgent always runs as the login that owns it.
    private static func mac(box: String, user: String) -> [String] {
        ["uid=$(id -u \(Shell.quote(user)) 2>/dev/null)",
         "[ -n \"$uid\" ] || fail 'this login is not known on this computer, so no boot registration was written'",
         "home=$(eval echo ~\(user) 2>/dev/null)",
         "[ -n \"$home\" ] || fail 'this login has no home folder on this computer, so no boot registration was written'",
         "plist=\"$home/\(agentFolder)/\(label).plist\""]
            + legacyRemoval
            + ["mkdir -p \"$home/\(agentFolder)\" || fail 'the LaunchAgents folder of this login could not be made'",
               "chown \(Shell.quote(user)) \"$home/\(agentFolder)\" >/dev/null 2>&1 || true",
               "cat > \"$plist\" <<'\(plistEnd)' || fail 'the boot registration file could not be written'"]
            + plist(box: box, user: user)
            + [plistEnd,
               "chmod 644 \"$plist\" || fail 'the boot registration file could not be given the usual rights'",
               "chown \(Shell.quote(user)) \"$plist\" || fail 'the boot registration file could not be given to this login'",
               "launchctl bootout gui/$uid/\(label) >/dev/null 2>&1 || true",
               "launchctl bootstrap gui/$uid \"$plist\" || fail 'the boot registration file was written, but launchd did not accept it: is that login signed in?'",
               "launchctl print gui/$uid/\(label) >/dev/null 2>&1 || fail 'launchd accepted the boot registration but does not list it'",
               "echo '\(InstallMissingScripts.detailMarker) this computer will now start its helper by itself when its login is signed in'"]
    }

    /// What the earlier design left in the system domain, removed before the LaunchAgent is loaded: its helper holds port 9101 and launchd would start it again
    /// seconds after `stop.sh`, so the new job could not bind. Best effort, and a Mac that never had these jobs is unchanged.
    private static let legacyRemoval = [
        "launchctl bootout system/\(label) >/dev/null 2>&1 || true",
        "rm -f \(legacyDaemonPath) >/dev/null 2>&1 || true",
        "launchctl bootout system/\(legacyContainerStartLabel) >/dev/null 2>&1 || true",
        "rm -f \(legacyContainerStartPath) >/dev/null 2>&1 || true",
    ]

    /// The LaunchAgent: the same flags `start.sh` writes, kept alive by launchd in the login's own domain. No `UserName` or `GroupName` — the job is that login's,
    /// and giving it one would put it back in the system domain.
    static func plist(box: String, user: String) -> [String] {
        let arguments = arguments(box: box, engine: macEngine).map { "    <string>\(xml($0))</string>" }
        let log = xml(box + "/" + logFile)
        return ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
                "<plist version=\"1.0\">",
                "<dict>",
                "  <key>Label</key>",
                "  <string>\(label)</string>",
                "  <key>ProgramArguments</key>",
                "  <array>"] + arguments + ["  </array>",
                                           "  <key>WorkingDirectory</key>",
                                           "  <string>\(xml(box))</string>",
                                           "  <key>RunAtLoad</key>",
                                           "  <true/>",
                                           "  <key>KeepAlive</key>",
                                           "  <true/>",
                                           "  <key>ThrottleInterval</key>",
                                           "  <integer>\(throttleSeconds)</integer>",
                                           "  <key>StandardOutPath</key>",
                                           "  <string>\(log)</string>",
                                           "  <key>StandardErrorPath</key>",
                                           "  <string>\(log)</string>",
                                           "</dict>",
                                           "</plist>"]
    }

    // MARK: Linux

    private static func linux(box: String, user: String) -> [String] {
        ["cat > \(linuxPath) <<'\(unitEnd)' || fail 'the unit file could not be written'"]
            + unit(box: box, user: user) + [unitEnd,
                                            "chmod 644 \(linuxPath) || fail 'the unit file could not be given the usual rights'",
                                            "chown root:root \(linuxPath) || fail 'the unit file could not be given to root'",
                                            "systemctl daemon-reload >/dev/null 2>&1 || fail 'the unit file was written, but systemd did not reload it'",
                                            "systemctl enable --now \(unitName) >/dev/null 2>&1 || fail 'the unit file was written, but systemd did not start the service'",
                                            "systemctl is-enabled --quiet \(unitName) || fail 'the unit file was written, but the service is not enabled for boot'",
                                            "echo '\(InstallMissingScripts.detailMarker) this computer will now start its helper by itself at boot'"]
    }

    /// The systemd unit: the same flags `start.sh` writes, as the login user from the box, restarted by systemd whenever it stops.
    static func unit(box: String, user: String) -> [String] {
        ["[Unit]",
         "Description=MetaService helper",
         "After=network-online.target",
         "",
         "[Service]",
         "User=\(user)",
         "WorkingDirectory=\(box)",
         "ExecStart=\(arguments(box: box, engine: linuxEngine).joined(separator: " "))",
         "Restart=always",
         "RestartSec=\(restartSeconds)",
         "",
         "[Install]",
         "WantedBy=multi-user.target"]
    }

    // MARK: shared

    /// The flags `start.sh` writes. The state folder stays relative, as there, because both services start the program in the box (`WorkingDirectory`).
    /// `--heartbeat-seconds` is here too: a service start must report to the parent as often as a `start.sh` start, or the parent would show it offline.
    static func arguments(box: String, engine: String) -> [String] {
        let port = RemoteInstallOptions.defaultAgentPort
        return [box + "/bin/" + InstallPlan.programName, "run", "--state-dir", stateFolder, "--engine", engine,
                "--port", String(port), "--bind", "127.0.0.1",
                "--chat-port", String(port + RemoteInstallOptions.chatPortOffset), "--chat-bind", "127.0.0.1",
                "--heartbeat-seconds", String(PlanScripts.heartbeatSeconds)]
    }

    /// A login name that can go into a unit file and a plist as it is: the shape a user name has on both systems. Anything else is refused, never written.
    static func isPlainLogin(_ user: String) -> Bool {
        !user.isEmpty && user.count <= 32 && user.unicodeScalars.allSatisfy { plainLogin.contains($0) }
    }

    private static let plainLogin = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

    private static func xml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
