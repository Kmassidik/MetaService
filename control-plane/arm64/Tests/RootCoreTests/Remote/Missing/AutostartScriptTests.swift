import XCTest
@testable import RootCore

/// "Starts at boot" is one fixed script: a LaunchAgent of the login on a Mac, a systemd unit on Linux, both naming the helper of the box with the flags `start.sh`
/// writes. Nothing here can install anything (it needs root on a real computer), so the checks are the text, the two documents, and what the system's own tools
/// accept.
final class AutostartScriptTests: XCTestCase {
    private let box = "/Users/mac/metaservice-box"
    private let user = "mac"
    private let plistMarker = "__METASERVICE_PLIST__"
    private let unitMarker = "__METASERVICE_UNIT__"
    /// The file the Mac half writes, as the script builds it from the login: never root's own home, which `$HOME` would be in a `sudo` script.
    private var plistPath: String { "$home/\(AutostartScript.agentFolder)/\(AutostartScript.label).plist" }

    private func script(box: String? = nil, user: String? = nil) -> String {
        AutostartScript.script(box: box ?? self.box, user: user ?? self.user)
    }

    private func parsed(_ text: String) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: Data(text.utf8), options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any])
    }

    /// The lines the script writes into one document, between the command that opens it and its closing marker.
    private func document(in text: String, opening: String, ending: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(opening) }), let stop = lines.firstIndex(of: ending), stop > start else { return [] }
        return Array(lines[(start + 1)..<stop])
    }

    /// The two halves of the script, as the computer's own answer (`uname -s`) tells them apart.
    private func halves(_ text: String) throws -> (mac: String, linux: String) {
        let split = try XCTUnwrap(text.range(of: "\nelse\n"))
        return (String(text[..<split.lowerBound]), String(text[split.upperBound...]))
    }

    private func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func testTheScriptAsksTheComputerWhichSystemItIsAndWritesBothKinds() {
        let text = script()
        for part in ["if [ \"$(uname -s)\" = Darwin ]; then", "cat > \"$plist\"", "launchctl bootstrap gui/$uid",
                     "cat > \(AutostartScript.linuxPath)", "systemctl daemon-reload", "systemctl enable --now \(AutostartScript.unitName)",
                     InstallMissingScripts.okMarker, InstallMissingScripts.doneMarker] {
            XCTAssertTrue(text.contains(part), part)
        }
        XCTAssertFalse(text.contains("aptget"), "nothing here is a package install")
        XCTAssertEqual(script(), script(), "the script is fixed text")
    }

    /// A Mac: the job is the login's own, so launchd keeps it up from that login's session and there is no `UserName` to put it in the system domain again.
    func testTheLaunchAgentNamesTheHelperOfTheBoxWithTheFlagsStartScriptUses() throws {
        let agent = try parsed(AutostartScript.plist(box: box, user: user).joined(separator: "\n"))
        XCTAssertEqual(agent["Label"] as? String, AutostartScript.label)
        XCTAssertNil(agent["UserName"], "a LaunchAgent runs as the login that owns it")
        XCTAssertNil(agent["GroupName"], "and with that login's group")
        XCTAssertEqual(agent["WorkingDirectory"] as? String, box)
        XCTAssertEqual(agent["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(agent["KeepAlive"] as? Bool, true)
        XCTAssertEqual(agent["ThrottleInterval"] as? Int, AutostartScript.throttleSeconds)
        XCTAssertEqual(agent["StandardOutPath"] as? String, box + "/logs/agent.log")
        XCTAssertEqual(agent["StandardErrorPath"] as? String, box + "/logs/agent.log")
        XCTAssertEqual(agent["ProgramArguments"] as? [String],
                       [box + "/bin/metaservice-agent", "run", "--state-dir", "state", "--engine", "apple", "--port", "9101", "--bind", "127.0.0.1",
                        "--chat-port", "9200", "--chat-bind", "127.0.0.1", "--heartbeat-seconds", "5"])
    }

    /// The document in the script is the one the generator makes, line for line: an XML declaration that is not the first byte is not a plist launchd reads.
    func testTheLaunchAgentGoesIntoTheScriptAsItIs() throws {
        let written = document(in: script(), opening: "cat > \"$plist\" <<'\(plistMarker)'", ending: plistMarker)
        XCTAssertEqual(written, AutostartScript.plist(box: box, user: user))
        XCTAssertEqual(written.first, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        XCTAssertNoThrow(try parsed(written.joined(separator: "\n")))
    }

    /// Where the file goes and how it is loaded: the home folder of the login (`id -u` for the domain, never root's `$HOME`), given to that login, and bootstrapped
    /// into `gui/<uid>` — the login's own domain, where Apple's container service lives. This half needs no `sudo`: the whole script already runs as root.
    func testTheLaunchAgentLivesInTheLoginFolderAndIsLoadedIntoItsGUIDomain() throws {
        let mac = try halves(script()).mac
        for part in ["uid=$(id -u 'mac' 2>/dev/null)", "home=$(eval echo ~mac 2>/dev/null)",
                     "plist=\"\(plistPath)\"", "mkdir -p \"$home/\(AutostartScript.agentFolder)\"",
                     "chown 'mac' \"$plist\"", "launchctl bootout gui/$uid/\(AutostartScript.label)", "launchctl bootstrap gui/$uid \"$plist\"",
                     "launchctl print gui/$uid/\(AutostartScript.label)"] {
            XCTAssertTrue(mac.contains(part), part)
        }
        XCTAssertTrue(mac.contains(AutostartScript.agentFolder) && mac.contains(AutostartScript.label + ".plist"),
                      "the job is a LaunchAgent of the login, under its home folder")
        for line in mac.split(separator: "\n") {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).hasPrefix("sudo"), "this half runs as root already: \(line)")
        }
        for line in mac.split(separator: "\n") where line.contains("/Library/LaunchDaemons") {
            XCTAssertTrue(line.contains("rm -f"), "the system folder is only cleaned up, never written: \(line)")
        }
    }

    /// The earlier design put this helper and a container starter in the system domain. Both go before anything is loaded: the old helper still holds port 9101,
    /// so it is stopped and its file deleted, best effort.
    func testTheJobsOfTheEarlierSystemDesignAreTakenAwayFirst() throws {
        let mac = try halves(script()).mac
        for part in ["launchctl bootout system/\(AutostartScript.label)",
                     "rm -f \(AutostartScript.legacyDaemonPath)",
                     "launchctl bootout system/\(AutostartScript.legacyContainerStartLabel)",
                     "rm -f \(AutostartScript.legacyContainerStartPath)"] {
            XCTAssertTrue(mac.contains(part), part)
        }
        for line in mac.split(separator: "\n") where line.contains("system/") && line.contains("launchctl") {
            XCTAssertFalse(line.contains("fail"), "an upgrade step never fails the install: \(line)")
        }
        let stop = try XCTUnwrap(mac.range(of: "cat > \"$plist\""))
        let oldHelper = try XCTUnwrap(mac.range(of: "launchctl bootout system/\(AutostartScript.label)"))
        XCTAssertLessThan(oldHelper.lowerBound, stop.lowerBound, "the old job is stopped before the new file is written")
        for line in script().split(separator: "\n") where line.contains("cat >") {
            XCTAssertFalse(line.contains("container-start"), "nothing writes the old container starter any more: \(line)")
        }
    }

    /// Linux: systemd starts the helper of the box at boot and restarts it whenever it stops.
    func testTheUnitRunsTheHelperOfTheBoxAndIsEnabledForBoot() {
        let unit = AutostartScript.unit(box: box, user: user)
        for part in ["[Unit]", "[Service]", "User=mac", "WorkingDirectory=\(box)", "Restart=always", "RestartSec=5", "[Install]", "WantedBy=multi-user.target"] {
            XCTAssertTrue(unit.contains(part), part)
        }
        XCTAssertTrue(unit.contains("ExecStart=\(box)/bin/metaservice-agent run --state-dir state --engine incus --port 9101 --bind 127.0.0.1 "
                                    + "--chat-port 9200 --chat-bind 127.0.0.1 --heartbeat-seconds 5"), unit.joined(separator: "\n"))
        XCTAssertEqual(document(in: script(), opening: "cat > \(AutostartScript.linuxPath)", ending: unitMarker), unit)
    }

    /// The Linux half is the same command lines it always was, to the letter: nothing about the Mac change may reach a Linux computer.
    func testTheLinuxHalfIsTheSameFixedLinesAsBefore() throws {
        let lines = try halves(script()).linux.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines, [
            "cat > /etc/systemd/system/metaservice-agent.service <<'__METASERVICE_UNIT__' || fail 'the unit file could not be written'",
            "[Unit]",
            "Description=MetaService helper",
            "After=network-online.target",
            "",
            "[Service]",
            "User=mac",
            "WorkingDirectory=/Users/mac/metaservice-box",
            "ExecStart=/Users/mac/metaservice-box/bin/metaservice-agent run --state-dir state --engine incus --port 9101 --bind 127.0.0.1 "
                + "--chat-port 9200 --chat-bind 127.0.0.1 --heartbeat-seconds 5",
            "Restart=always",
            "RestartSec=5",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "__METASERVICE_UNIT__",
            "chmod 644 /etc/systemd/system/metaservice-agent.service || fail 'the unit file could not be given the usual rights'",
            "chown root:root /etc/systemd/system/metaservice-agent.service || fail 'the unit file could not be given to root'",
            "systemctl daemon-reload >/dev/null 2>&1 || fail 'the unit file was written, but systemd did not reload it'",
            "systemctl enable --now metaservice-agent >/dev/null 2>&1 || fail 'the unit file was written, but systemd did not start the service'",
            "systemctl is-enabled --quiet metaservice-agent || fail 'the unit file was written, but the service is not enabled for boot'",
            "echo 'ms-detail: this computer will now start its helper by itself at boot'",
            "fi",
            "echo ms-done",
            "",
        ])
    }

    /// The box has to be there: a computer without one is not ours, and a service pointed at a folder that does not exist would fail at every boot.
    func testTheScriptRefusesAComputerWithoutABoxOfOurs() {
        let text = script()
        XCTAssertTrue(text.contains("box='\(box)'"))
        XCTAssertTrue(text.contains("[ -d \"$box\" ] || fail"), "the folder is checked before anything is written")
        XCTAssertTrue(text.contains("there is nothing to register"))
    }

    /// The login name goes into a unit file and a plist as it is, so a name that is not a plain user name is refused instead of written.
    func testALoginNameThatIsNotAPlainUserNameIsRefused() {
        for name in ["", "root; rm -rf /", "a b", "../etc", "mac\nUser=root", String(repeating: "a", count: 33)] {
            let text = AutostartScript.script(box: box, user: name)
            XCTAssertFalse(text.contains("launchctl"), name)
            XCTAssertFalse(text.contains("systemctl"), name)
            XCTAssertTrue(text.contains(InstallMissingScripts.errorMarker), name)
        }
        XCTAssertTrue(AutostartScript.isPlainLogin("mac"))
        XCTAssertTrue(AutostartScript.isPlainLogin("build.user-1_x"))
    }

    /// What the system's own tools say about the two things this part produces: `plutil` reads the plist launchd is given, and the whole script is one shell command.
    func testTheProducedDocumentsAreAcceptedByTheSystemTools() throws {
        let path = NSTemporaryDirectory() + AutostartScript.label + ".plist"
        try AutostartScript.plist(box: box, user: user).joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertEqual(try run("/usr/bin/plutil", ["-lint", path]), 0, "launchd reads a plist, not a text file")
        XCTAssertEqual(try run("/bin/sh", ["-n", "-c", script()]), 0, "the script is accepted by the shell before it is run")
    }
}
