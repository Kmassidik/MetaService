import XCTest
@testable import AgentCore

private struct FakeFiles: SshdConfigFiles, MacFiles {
    var texts: [String: String] = [:]
    var directories: [String: [String]] = [:]

    func read(_ path: String) -> String? { texts[path] }
    func read(_ path: String) -> Data? { texts[path].map { Data($0.utf8) } }
    func list(_ directory: String) -> [String]? { directories[directory] }

    /// Only `dir/*` patterns, like Apple's own Include line.
    func expand(_ pattern: String) -> [String] {
        let directory = (pattern as NSString).deletingLastPathComponent
        return (directories[directory] ?? []).sorted().map { directory + "/" + $0 }
    }
}

private func answering(_ outputs: [String: String]) -> BaselineChecks.Run {
    { executable, arguments in
        guard let text = outputs[([executable] + arguments).joined(separator: " ")] else { throw CocoaError(.fileNoSuchFile) }
        return Data(text.utf8)
    }
}

final class SshdConfigResolverTests: XCTestCase {
    private func resolve(_ main: String?, _ extra: [String: String] = [:], directory: [String] = []) -> Bool? {
        var files = FakeFiles(texts: extra, directories: ["/etc/ssh/sshd_config.d": directory])
        files.texts["/etc/ssh/sshd_config"] = main
        return SshdConfigResolver(files: files).passwordLogin()
    }

    func testWithNothingSayingSoPasswordLoginIsOn() {
        XCTAssertEqual(resolve("UsePAM yes\nAcceptEnv LANG LC_*\n"), true)
        XCTAssertEqual(resolve(""), true)
        XCTAssertEqual(resolve("# PasswordAuthentication no\n"), true, "a comment says nothing")
    }

    func testTheFirstValueWins() {
        XCTAssertEqual(resolve("PasswordAuthentication no\nPasswordAuthentication yes\n"), false)
        XCTAssertEqual(resolve("passwordauthentication YES\nPasswordAuthentication no\n"), true, "keyword and value are not case sensitive")
        XCTAssertEqual(resolve("  PasswordAuthentication\tno  # because\n"), false)
        XCTAssertEqual(resolve("PasswordAuthentication=no\n"), false)
        XCTAssertEqual(resolve("PasswordAuthentication = \"no\"\n"), false)
    }

    func testAnIncludeIsReadWhereItStands() {
        let extra = ["/etc/ssh/sshd_config.d/100-macos.conf": "PasswordAuthentication no\n", "/etc/ssh/sshd_config.d/200-late.conf": "PasswordAuthentication yes\n"]
        let both = ["100-macos.conf", "200-late.conf"]
        XCTAssertEqual(resolve("Include /etc/ssh/sshd_config.d/*\nPasswordAuthentication yes\n", extra, directory: both), false, "the include comes first")
        XCTAssertEqual(resolve("PasswordAuthentication yes\nInclude /etc/ssh/sshd_config.d/*\n", extra, directory: both), true, "the line before it wins")
        XCTAssertEqual(resolve("Include sshd_config.d/*\n", extra, directory: both), false, "a relative pattern starts in /etc/ssh")
    }

    func testAnIncludeThatMatchesNothingIsFine() {
        XCTAssertEqual(resolve("Include /etc/ssh/sshd_config.d/*\n", directory: []), true)
    }

    func testMatchBlocksAreSkipped() {
        XCTAssertEqual(resolve("Match User backup\n  PasswordAuthentication no\n"), true)
        XCTAssertEqual(resolve("PasswordAuthentication no\nMatch User x\n  PasswordAuthentication yes\n"), false)
        let extra = ["/etc/ssh/sshd_config.d/10.conf": "Match User x\nPasswordAuthentication yes\n", "/etc/ssh/sshd_config.d/20.conf": "PasswordAuthentication no\n"]
        XCTAssertEqual(resolve("Include /etc/ssh/sshd_config.d/*\n", extra, directory: ["10.conf", "20.conf"]), false, "a Match inside an included file ends with that file")
    }

    func testUnreadableOrUnintelligibleIsUnknown() {
        XCTAssertNil(resolve(nil))
        XCTAssertNil(resolve("Include /etc/ssh/sshd_config.d/*\n", directory: ["gone.conf"]), "an included file that cannot be read")
        XCTAssertNil(resolve("PasswordAuthentication maybe\n"))
        XCTAssertNil(resolve("PasswordAuthentication\n"))
        XCTAssertEqual(resolve("PasswordAuthentication no\nInclude /etc/ssh/sshd_config.d/*\n", directory: ["gone.conf"]), false, "the answer was found before the unreadable file")
    }

    func testAnIncludeLoopStops() {
        let extra = ["/etc/ssh/sshd_config.d/loop.conf": "Include /etc/ssh/sshd_config.d/*\n"]
        XCTAssertNil(resolve("Include /etc/ssh/sshd_config.d/*\n", extra, directory: ["loop.conf"]))
    }
}

final class BaselineChecksTests: XCTestCase {
    private let firewallCommand = "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate"
    private let updatesCommand = "/usr/bin/defaults export /Library/Preferences/com.apple.SoftwareUpdate -"
    private let loginCommand = "/usr/bin/defaults export /Library/Preferences/com.apple.loginwindow -"

    private func plist(_ body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>\(body)</dict></plist>"
    }

    func testTheFirewallStateMapsToABoolean() async {
        let states = [("Firewall is disabled. (State = 0)", false), ("Firewall is enabled. (State = 1)", true), ("Firewall is blocking all non-essential incoming connections. (State = 2)", true)]
        for (text, expected) in states {
            let found = await BaselineChecks.firewall(run: answering([firewallCommand: text]))
            XCTAssertEqual(found, expected, text)
        }
        let strange = await BaselineChecks.firewall(run: answering([firewallCommand: "State = 7"]))
        let silent = await BaselineChecks.firewall(run: answering([firewallCommand: ""]))
        let failed = await BaselineChecks.firewall(run: answering([:]))
        XCTAssertNil(strange)
        XCTAssertNil(silent)
        XCTAssertNil(failed)
    }

    func testAutoUpdatesNeedBothSwitchesOn() async {
        let on = plist("<key>AutomaticallyInstallMacOSUpdates</key><integer>1</integer><key>CriticalUpdateInstall</key><true/>")
        let onlyOne = plist("<key>AutomaticallyInstallMacOSUpdates</key><integer>1</integer><key>CriticalUpdateInstall</key><integer>0</integer>")
        let missing = plist("<key>AutomaticCheckEnabled</key><true/><key>AutomaticDownload</key><true/>")
        let empty = plist("")
        let expectations: [(String, Bool)] = [(on, true), (onlyOne, false), (missing, false), (empty, false)]
        for (text, expected) in expectations {
            let found = await BaselineChecks.autoUpdates(run: answering([updatesCommand: text]))
            XCTAssertEqual(found, expected, text)
        }
    }

    func testAutoUpdatesAreUnknownWhenUnreadable() async {
        let failed = await BaselineChecks.autoUpdates(run: answering([:]))
        let garbage = await BaselineChecks.autoUpdates(run: answering([updatesCommand: "not a plist"]))
        XCTAssertNil(failed)
        XCTAssertNil(garbage)
    }

    private func job(label: String = "io.metaservice.agent", program: String = "/opt/metaservice-agent", extra: String) -> String {
        plist("<key>Label</key><string>\(label)</string><key>ProgramArguments</key><array><string>\(program)</string></array>\(extra)")
    }

    func testALaunchDaemonThatRunsAtLoadStartsAfterAReboot() async {
        for extra in ["<key>RunAtLoad</key><true/>", "<key>KeepAlive</key><true/>", "<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>"] {
            let files = FakeFiles(texts: ["/Library/LaunchDaemons/a.plist": job(extra: extra)], directories: ["/Library/LaunchDaemons": ["a.plist"]])
            let found = await BaselineChecks.startsAfterReboot(files: files, homeDirectory: "/Users/u", run: answering([:]))
            XCTAssertEqual(found, true, extra)
        }
    }

    func testAJobThatIsOtherwiseOrDoesNotStartItselfDoesNotCount() async {
        let files = FakeFiles(texts: ["/Library/LaunchDaemons/a.plist": job(extra: "<key>RunAtLoad</key><false/>"),
                                      "/Library/LaunchDaemons/b.plist": job(label: "other", program: "/usr/bin/other", extra: "<key>RunAtLoad</key><true/>"),
                                      "/Library/LaunchDaemons/c.plist": "garbage", "/Library/LaunchDaemons/d.txt": job(extra: "<key>RunAtLoad</key><true/>")],
                              directories: ["/Library/LaunchDaemons": ["a.plist", "b.plist", "c.plist", "d.txt"]])
        let found = await BaselineChecks.startsAfterReboot(files: files, homeDirectory: "/Users/u", run: answering([:]))
        XCTAssertEqual(found, false)
    }

    func testALaunchAgentCountsOnlyWithAutomaticLogin() async {
        let files = FakeFiles(texts: ["/Users/u/Library/LaunchAgents/a.plist": job(extra: "<key>RunAtLoad</key><true/>")],
                              directories: ["/Library/LaunchDaemons": [], "/Users/u/Library/LaunchAgents": ["a.plist"]])
        let withLogin = await BaselineChecks.startsAfterReboot(files: files, homeDirectory: "/Users/u", run: answering([loginCommand: plist("<key>autoLoginUser</key><string>u</string>")]))
        let withoutLogin = await BaselineChecks.startsAfterReboot(files: files, homeDirectory: "/Users/u", run: answering([loginCommand: plist("")]))
        let unreadable = await BaselineChecks.startsAfterReboot(files: files, homeDirectory: "/Users/u", run: answering([:]))
        XCTAssertEqual(withLogin, true)
        XCTAssertEqual(withoutLogin, false)
        XCTAssertNil(unreadable)
    }

    func testNoJobAtAllIsFalseAndAnUnlistableDaemonsFolderIsUnknown() async {
        let none = FakeFiles(directories: ["/Library/LaunchDaemons": []])
        let noneFound = await BaselineChecks.startsAfterReboot(files: none, homeDirectory: "/Users/u", run: answering([:]))
        let unlistable = await BaselineChecks.startsAfterReboot(files: FakeFiles(), homeDirectory: "/Users/u", run: answering([:]))
        XCTAssertEqual(noneFound, false)
        XCTAssertNil(unlistable)
    }
}

final class PendingUpdatesTests: XCTestCase {
    private final class Clock: @unchecked Sendable { var now: TimeInterval = 1000 }

    func testOneUpdateForEachLabelLine() {
        let text = """
        Software Update Tool

        Finding available software
        Software Update found the following new or updated software:
        * Label: Safari27.2TahoeAuto-27.2
        \tTitle: Safari, Version: 27.2, Size: 250130KiB, Recommended: YES,
        * Label: macOS Tahoe 26.7.2-25G332
        \tTitle: macOS Tahoe 26.7.2, Version: 26.7.2, Recommended: YES, Action: restart,
        """
        XCTAssertEqual(PendingUpdates.count(text), 2)
        XCTAssertEqual(PendingUpdates.count("Software Update Tool\n\nFinding available software\nNo new software available.\n"), 0)
        XCTAssertEqual(PendingUpdates.count(""), 0)
    }

    func testTheCountIsKeptForThirtyMinutes() async {
        let clock = Clock()
        let asked = Counter()
        let updates = PendingUpdates(now: { clock.now }, run: { _, arguments, timeout in
            XCTAssertEqual(arguments, ["-l"])
            XCTAssertEqual(timeout, 60)
            return Data(asked.next() == 1 ? "* Label: a\n* Label: b\n".utf8 : "".utf8)
        })
        await updates.refresh()
        XCTAssertEqual(updates.current(), 2)
        clock.now += 29 * 60
        XCTAssertEqual(updates.current(), 2)
        XCTAssertEqual(asked.value, 1, "still inside the 30 minutes: no new run")
    }

    func testAFailedRunGivesNil() async {
        let clock = Clock()
        let updates = PendingUpdates(now: { clock.now }, run: { _, _, _ in throw CocoaError(.fileNoSuchFile) })
        await updates.refresh()
        XCTAssertNil(updates.current())
    }
}

private final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func next() -> Int { value += 1; return value }
}
