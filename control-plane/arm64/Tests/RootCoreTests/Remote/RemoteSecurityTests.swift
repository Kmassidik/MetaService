import XCTest
@testable import RootCore

final class RemoteSecurityTests: XCTestCase {
    private let ubuntu = """
    password_login=yes
    ban_tool=not_running
    firewall=no
    auto_updates=no
    has_key_login=yes
    pending_updates=7
    """
    private let mac = """
    password_login=no
    ban_tool=not_available
    firewall=yes
    auto_updates=yes
    has_key_login=no
    pending_updates=0
    """

    func testAnUbuntuAnswerIsRead() {
        let security = RemoteSecurityParse.parse(ubuntu)
        XCTAssertEqual(security.passwordLogin, true)
        XCTAssertEqual(security.banTool, .notRunning)
        XCTAssertEqual(security.firewall, false)
        XCTAssertEqual(security.autoUpdates, false)
        XCTAssertEqual(security.hasKeyLogin, true)
        XCTAssertEqual(security.pendingUpdates, 7)
    }

    func testAMacAnswerIsRead() {
        let security = RemoteSecurityParse.parse(mac)
        XCTAssertEqual([security.passwordLogin, security.firewall, security.autoUpdates, security.hasKeyLogin], [false, true, true, false])
        XCTAssertEqual(security.banTool, .notAvailable)
        XCTAssertEqual(security.pendingUpdates, 0)
    }

    func testUnknownAndMissingStayUnknown() {
        let security = RemoteSecurityParse.parse("password_login=unknown\nban_tool=unknown\nfirewall=maybe\npending_updates=unknown\n")
        XCTAssertEqual(security, RemoteSecurity())
        XCTAssertEqual(RemoteSecurityParse.parse(""), RemoteSecurity())
    }

    func testHostileOutputIsIgnored() {
        let hugeLine = "password_login=" + String(repeating: "y", count: 5000)
        let hostile = [
            "password_login=yes; rm -rf /", "ban_tool=$(reboot)", "firewall=\u{1B}[31myes", "auto_updates=yes\u{0}", "extra_key=yes", "pending_updates=-4",
            "pending_updates=1e3", "pending_updates=99999999999999999999", "pending_updates=100001", hugeLine, "has_key_login=`id`",
        ].joined(separator: "\n")
        XCTAssertEqual(RemoteSecurityParse.parse(hostile), RemoteSecurity())
    }

    func testTheFirstLineOfAKeyWinsAndALimitIsKept() {
        XCTAssertEqual(RemoteSecurityParse.parse("firewall=no\nfirewall=yes\n").firewall, false)
        XCTAssertEqual(RemoteSecurityParse.parse("pending_updates=100000\n").pendingUpdates, 100_000)
        let flood = String(repeating: "junk=1\n", count: 500) + "firewall=yes\n"
        XCTAssertNil(RemoteSecurityParse.parse(flood).firewall, "lines past the limit are not read")
        XCTAssertEqual(RemoteSecurityParse.parse("firewall=yes\r\nban_tool=running\r\n").banTool, .running, "a Windows line end is a line end")
    }

    func testTheReplyAlwaysNamesEveryKeyWithNullForUnknown() throws {
        let data = try JSONEncoder().encode(RemoteSecurityParse.parse("firewall=yes\npending_updates=3\n"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["password_login", "ban_tool", "firewall", "auto_updates", "pending_updates", "has_key_login"])
        XCTAssertEqual(object["firewall"] as? Bool, true)
        XCTAssertEqual(object["pending_updates"] as? Int, 3)
        XCTAssertTrue(object["password_login"] is NSNull)
    }

    // MARK: the script

    func testTheScriptOnlyReads() {
        let script = SecurityVerifyScript.script
        XCTAssertTrue(script.hasPrefix(SecurityVerifyScript.marker))
        for writer in ["sudo", " rm ", "> /", ">> ", "tee ", "systemctl start", "systemctl enable", "apt install", "apt-get", "chmod", "mktemp", "ufw enable"] {
            XCTAssertFalse(script.contains(writer), "the script must not contain \(writer)")
        }
    }

    // The password rule is run for real by /bin/sh against a folder that stands for /etc/ssh.
    private func passwordLogin(_ files: [String: String]) throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ms-sshd-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = root.appendingPathComponent("etc/ssh")
        try FileManager.default.createDirectory(at: ssh.appendingPathComponent("sshd_config.d"), withIntermediateDirectories: true)
        for (name, text) in files { try text.write(to: ssh.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        let probe = SecurityVerifyScript.make(root: root.path).replacingOccurrences(of: #"case "$(uname -s)" in"#, with: "password_login\nexit 0\ncase x in")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "script=$(cat); eval \"$script\" | tail -1; true"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(probe.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    func testPasswordLoginFollowsSshdsOwnRules() throws {
        XCTAssertEqual(try passwordLogin(["sshd_config": "Port 22\n"]), "yes", "nothing said means yes")
        XCTAssertEqual(try passwordLogin(["sshd_config": "PasswordAuthentication no\n"]), "no")
        XCTAssertEqual(try passwordLogin(["sshd_config": "passwordauthentication=NO # comment\n"]), "no", "any case, = or space, comments cut")
        XCTAssertEqual(try passwordLogin(["sshd_config": "PasswordAuthentication yes\nPasswordAuthentication no\n"]), "yes", "the first value wins")
        XCTAssertEqual(try passwordLogin(["sshd_config": "Match User bob\nPasswordAuthentication no\n"]), "yes", "a Match block is skipped")
        XCTAssertEqual(try passwordLogin(["sshd_config": "#PasswordAuthentication no\n"]), "yes", "a comment says nothing")
    }

    func testIncludeIsExpandedWhereItStands() throws {
        let include = "Include /etc/ssh/sshd_config.d/*.conf\nPasswordAuthentication yes\n"
        XCTAssertEqual(try passwordLogin(["sshd_config": include, "sshd_config.d/50-cloud.conf": "PasswordAuthentication no\n"]), "no", "the include comes first")
        XCTAssertEqual(try passwordLogin(["sshd_config": "PasswordAuthentication yes\nInclude sshd_config.d/*.conf\n", "sshd_config.d/00.conf": "PasswordAuthentication no\n"]), "yes")
        XCTAssertEqual(try passwordLogin(["sshd_config": "Include sshd_config.d/*.conf\n"]), "yes", "an include that matches nothing is fine")
    }

    func testAnUnreadableMainFileIsUnknown() throws {
        XCTAssertEqual(try passwordLogin([:]), "unknown")
    }
}
