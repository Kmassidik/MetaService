import XCTest
@testable import RootCore

/// "Starts at boot" is one fixed script: a LaunchDaemon on a Mac, a systemd unit on Linux, both naming the helper of the box with the flags `start.sh` writes.
/// Nothing here can install anything (it needs root on a real computer), so the checks are the text, the two documents, and what the shell accepts.
final class AutostartScriptTests: XCTestCase {
    private let box = "/Users/mac/metaservice-box"
    private let user = "mac"
    private let plistMarker = "__METASERVICE_PLIST__"
    private let unitMarker = "__METASERVICE_UNIT__"

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

    /// The text between the line that opens one document and its closing marker, as it is: the container program in it has lines of its own.
    private func section(in text: String, opening: String, ending: String) -> String {
        guard let start = text.range(of: opening + " <<'"), let stop = text.range(of: "\n" + ending + "\n", range: start.upperBound..<text.endIndex),
              let openingLineEnd = text.range(of: "\n", range: start.lowerBound..<stop.lowerBound) else { return "" }
        return String(text[openingLineEnd.upperBound..<stop.lowerBound])
    }

    func testTheScriptAsksTheComputerWhichSystemItIsAndWritesBothKinds() {
        let text = script()
        for part in ["if [ \"$(uname -s)\" = Darwin ]; then", "cat > \(AutostartScript.macPath)", "launchctl bootstrap system \(AutostartScript.macPath)",
                     "cat > \(AutostartScript.linuxPath)", "systemctl daemon-reload", "systemctl enable --now \(AutostartScript.unitName)",
                     InstallMissingScripts.okMarker, InstallMissingScripts.doneMarker] {
            XCTAssertTrue(text.contains(part), part)
        }
        XCTAssertFalse(text.contains("aptget"), "nothing here is a package install")
        XCTAssertEqual(script(), script(), "the script is fixed text")
    }

    /// A Mac: the helper runs as the login user, not as root, and launchd keeps it up from boot.
    func testTheLaunchDaemonNamesTheHelperOfTheBoxWithTheFlagsStartScriptUses() throws {
        let daemon = try parsed(AutostartScript.plist(box: box, user: user).joined(separator: "\n"))
        XCTAssertEqual(daemon["Label"] as? String, AutostartScript.label)
        XCTAssertEqual(daemon["UserName"] as? String, "mac")
        XCTAssertEqual(daemon["WorkingDirectory"] as? String, box)
        XCTAssertEqual(daemon["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(daemon["KeepAlive"] as? Bool, true)
        XCTAssertEqual(daemon["ThrottleInterval"] as? Int, AutostartScript.throttleSeconds)
        XCTAssertEqual(daemon["StandardOutPath"] as? String, box + "/logs/agent.log")
        XCTAssertEqual(daemon["StandardErrorPath"] as? String, box + "/logs/agent.log")
        XCTAssertEqual(daemon["ProgramArguments"] as? [String],
                       [box + "/bin/metaservice-agent", "run", "--state-dir", "state", "--engine", "apple", "--port", "9101", "--bind", "127.0.0.1",
                        "--chat-port", "9200", "--chat-bind", "127.0.0.1", "--heartbeat-seconds", "5"])
    }

    /// The document in the script is the one the generator makes, line for line: an XML declaration that is not the first byte is not a plist launchd reads.
    func testTheLaunchDaemonGoesIntoTheScriptAsItIs() throws {
        let written = document(in: script(), opening: "cat > \(AutostartScript.macPath)", ending: plistMarker)
        XCTAssertEqual(written, AutostartScript.plist(box: box, user: user))
        XCTAssertEqual(written.first, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        XCTAssertNoThrow(try parsed(written.joined(separator: "\n")))
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

    // MARK: Apple's container service

    /// The second daemon of a Mac: it runs once at boot, as root, because only root may enter the login's session where Apple's container service lives.
    func testTheContainerStartDaemonRunsOnceAtBootAsRoot() throws {
        let daemon = try parsed(AutostartScript.containerStartPlist(box: box, user: user).joined(separator: "\n"))
        XCTAssertEqual(daemon["Label"] as? String, "io.metaservice.container-start")
        XCTAssertNil(daemon["UserName"], "root, with no login of its own")
        XCTAssertEqual(daemon["RunAtLoad"] as? Bool, true)
        XCTAssertNil(daemon["KeepAlive"], "one start at boot, never restarted in a loop")
        XCTAssertEqual(daemon["StandardOutPath"] as? String, box + "/logs/container-start.log")
        XCTAssertEqual(daemon["StandardErrorPath"] as? String, box + "/logs/container-start.log")
        let arguments = try XCTUnwrap(daemon["ProgramArguments"] as? [String])
        XCTAssertEqual(Array(arguments.prefix(2)), ["/bin/sh", "-c"])
        XCTAssertEqual(arguments.count, 3, "one fixed program, run by sh")
        XCTAssertEqual(arguments.last, AutostartScript.containerStartCommand(user: user), "the script survives the plist as it was written")
    }

    /// The program it runs: the `container` program wherever that computer keeps it, then the login's own session, which is the only place its service starts.
    func testTheContainerStartCommandFindsTheToolAndUsesTheLoginOfTheCheck() {
        let command = AutostartScript.containerStartCommand(user: user)
        for part in ["/usr/local/bin/container", "/opt/homebrew/bin/container", "/usr/bin/container",
                     "tool=\"$candidate\"", "[ -z \"$tool\" ]",
                     "uid=$(id -u 'mac' 2>/dev/null)", "launchctl asuser \"$uid\" sudo -u 'mac' \"$tool\" system start"] {
            XCTAssertTrue(command.contains(part), part)
        }
        XCTAssertTrue(command.hasSuffix("|| true"), "the job of a boot never fails the install")
        XCTAssertEqual(command, AutostartScript.containerStartCommand(user: user), "the program is fixed text")
        XCTAssertEqual(command.components(separatedBy: "launchctl asuser").count - 1, 1, "one start, not a loop")
    }

    /// The document in the script is the one the generator makes, and it is registered as root the way the helper's own file is.
    func testTheContainerStartDaemonIsWrittenAndRegisteredBestEffort() throws {
        let text = script()
        let written = section(in: text, opening: "cat > \(AutostartScript.containerStartPath)", ending: "__METASERVICE_CONTAINER_PLIST__")
        XCTAssertEqual(written, AutostartScript.containerStartPlist(box: box, user: user).joined(separator: "\n"))
        XCTAssertTrue(written.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"), "an XML declaration that is not the first byte is not a plist launchd reads")
        XCTAssertNoThrow(try parsed(written))
        for part in ["chmod 644 \(AutostartScript.containerStartPath)", "chown root:wheel \(AutostartScript.containerStartPath)",
                     "launchctl bootout system/io.metaservice.container-start",
                     "launchctl bootstrap system \(AutostartScript.containerStartPath)"] {
            XCTAssertTrue(text.contains(part), part)
        }
        for line in text.split(separator: "\n") where line.contains(AutostartScript.containerStartPath) && line.contains("fail") {
            XCTFail("the container start file never fails the install: \(line)")
        }
        XCTAssertNotEqual(written, AutostartScript.plist(box: box, user: user).joined(separator: "\n"), "two files, two jobs")
    }

    /// Linux starts `incus` itself, so its half of the script writes nothing about Apple's container service.
    func testLinuxWritesNoContainerStartFile() throws {
        let text = script()
        let linuxHalf = try XCTUnwrap(text.range(of: "\nelse\n")).upperBound
        let linux = String(text[linuxHalf...])
        XCTAssertTrue(linux.contains(AutostartScript.linuxPath), "the unit is in this half")
        XCTAssertFalse(linux.contains(AutostartScript.containerStartPath), "Apple's service is not a Linux thing")
        let macHalf = String(text[..<linuxHalf])
        XCTAssertTrue(macHalf.contains("cat > \(AutostartScript.containerStartPath)"))
    }
}
