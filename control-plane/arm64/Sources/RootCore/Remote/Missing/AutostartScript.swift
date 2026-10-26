import Foundation

/// The part of "Install it for me" that registers a helper which is already installed with the system's own boot service: a LaunchDaemon on a Mac, a systemd
/// unit on Linux. Nothing about the helper changes: both run `<box>/bin/metaservice-agent` with the flags `start.sh` writes, as the login user, from the box.
///
/// Without it a restart leaves that machine offline until somebody runs `~/metaservice-box/start.sh`, so the parent is green while its machines are grey
/// (seen on 2026-10-26, after two power cycles). The script is fixed text: the only things in it are the login user and the box of that computer, both read by
/// the check, never sent by the browser.
enum AutostartScript {
    static let label = "io.metaservice.agent"
    static let macPath = "/Library/LaunchDaemons/" + label + ".plist"
    static let unitName = "metaservice-agent"
    static let linuxPath = "/etc/systemd/system/" + unitName + ".service"

    /// Apple's container service belongs to one login, not to the whole computer: the helper's own `container system start` runs in the system domain and does
    /// nothing there. This second daemon runs once at boot as root and asks that login to start it (see `containerStartCommand`).
    static let containerStartLabel = "io.metaservice.container-start"
    static let containerStartPath = "/Library/LaunchDaemons/" + containerStartLabel + ".plist"

    /// launchd restarts a job no sooner than this, so a program that fails at once cannot fill the disk with its own log.
    static let throttleSeconds = 10
    static let restartSeconds = 5
    /// The process stops on SIGTERM; the port has to be free before the service takes its place.
    private static let stopWaitSeconds = 2
    private static let stateFolder = "state"
    private static let logFile = "logs/agent.log"
    private static let containerStartLogFile = "logs/container-start.log"
    /// Where the `container` program of Apple's own install can be: Homebrew on Apple silicon, Homebrew on Intel, and a plain `/usr/bin` install.
    static let containerToolPaths = ["/usr/local/bin/container", "/opt/homebrew/bin/container", "/usr/bin/container"]
    private static let macEngine = "apple"
    private static let linuxEngine = "incus"
    private static let plistEnd = "__METASERVICE_PLIST__"
    private static let containerPlistEnd = "__METASERVICE_CONTAINER_PLIST__"
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

    private static func mac(box: String, user: String) -> [String] {
        ["cat > \(macPath) <<'\(plistEnd)' || fail 'the boot registration file could not be written'"]
            + plist(box: box, user: user) + [plistEnd,
                                             "chmod 644 \(macPath) || fail 'the boot registration file could not be given the usual rights'",
                                             "chown root:wheel \(macPath) || fail 'the boot registration file could not be given to root'",
                                             "launchctl bootout system/\(label) >/dev/null 2>&1 || true",
                                             "launchctl bootstrap system \(macPath) || fail 'the boot registration file was written, but launchd did not accept it'",
                                             "launchctl print system/\(label) >/dev/null 2>&1 || fail 'launchd accepted the boot registration but does not list it'",
                                             "echo '\(InstallMissingScripts.detailMarker) this computer will now start its helper by itself at boot'"]
            + containerStart(box: box, user: user)
    }

    /// The second daemon of a Mac, and nothing a failure here can undo: the helper is registered above and is all the panel waits for, so a computer whose
    /// launchd refuses this one still installs, and the marker says that Apple's containers will need starting by hand after a restart.
    private static func containerStart(box: String, user: String) -> [String] {
        ["cat > \(containerStartPath) <<'\(containerPlistEnd)' || echo '\(refusedDetail)'"]
            + containerStartPlist(box: box, user: user) + [containerPlistEnd,
                                                            "chmod 644 \(containerStartPath) >/dev/null 2>&1 || true",
                                                            "chown root:wheel \(containerStartPath) >/dev/null 2>&1 || true",
                                                            "launchctl bootout system/\(containerStartLabel) >/dev/null 2>&1 || true",
                                                            "launchctl bootstrap system \(containerStartPath) >/dev/null 2>&1 || echo '\(refusedDetail)'"]
    }

    private static let refusedDetail = InstallMissingScripts.detailMarker
        + " launchd did not accept the file that starts Apple's container service, so Apple's containers may need starting by hand after a restart"

    /// The one-shot LaunchDaemon: no `UserName`, so it runs as root (only root may enter another login's session), `RunAtLoad` and no `KeepAlive`, so it starts
    /// the service once at boot and is never restarted in a loop.
    static func containerStartPlist(box: String, user: String) -> [String] {
        let arguments = ["/bin/sh", "-c", containerStartCommand(user: user)].map { "    <string>\(xml($0))</string>" }
        let log = xml(box + "/" + containerStartLogFile)
        return ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
                "<plist version=\"1.0\">",
                "<dict>",
                "  <key>Label</key>",
                "  <string>\(containerStartLabel)</string>",
                "  <key>ProgramArguments</key>",
                "  <array>"] + arguments + ["  </array>",
                                           "  <key>RunAtLoad</key>",
                                           "  <true/>",
                                           "  <key>WorkingDirectory</key>",
                                           "  <string>\(xml(box))</string>",
                                           "  <key>StandardOutPath</key>",
                                           "  <string>\(log)</string>",
                                           "  <key>StandardErrorPath</key>",
                                           "  <string>\(log)</string>",
                                           "</dict>",
                                           "</plist>"]
    }

    /// The fixed program of that daemon: the first `container` of the three places it is installed to, then the login's own session (`launchctl asuser`) for
    /// `container system start`. The login name comes from the check, and the number is the system's own answer for that name — never anything the browser sent.
    /// Every step that cannot go on ends with success and a line in the log, so a boot never turns into a failed job.
    static func containerStartCommand(user: String) -> String {
        let login = Shell.quote(user)
        return ["tool=",
                "for candidate in \(containerToolPaths.joined(separator: " ")); do",
                "  [ -x \"$candidate\" ] || continue",
                "  tool=\"$candidate\"",
                "  break",
                "done",
                "if [ -z \"$tool\" ]; then echo 'no container program to start'; exit 0; fi",
                "uid=$(id -u \(login) 2>/dev/null) || uid=",
                "if [ -z \"$uid\" ]; then echo 'no login to start Apple containers for'; exit 0; fi",
                "launchctl asuser \"$uid\" sudo -u \(login) \"$tool\" system start || true"].joined(separator: "\n")
    }


    /// The LaunchDaemon: the same flags `start.sh` writes, as the login user (the helper of that computer, not root), kept alive by launchd.
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
                                           "  <key>UserName</key>",
                                           "  <string>\(xml(user))</string>",
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
