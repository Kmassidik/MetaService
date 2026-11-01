import XCTest
@testable import RootCore

/// The Linux half of the look, run for real by /bin/sh against a folder that stands for /etc and a bin folder of stubs (`uname`, `systemctl`, `apt`, `timeout`),
/// so the same rules the helper has are checked without a Linux computer.
final class SecurityVerifyLinuxTests: XCTestCase {
    private struct Machine {
        var files: [String: String] = [:]
        /// unit name -> "LoadState ActiveState UnitFileState"
        var units: [String: String] = [:]
        var apt: String? = "Listing...\n"
        var keys: String?
    }

    private func unit(_ load: String, _ active: String, _ file: String) -> String { "\(load) \(active) \(file)" }

    private func run(_ machine: Machine) throws -> [String: String] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ms-lin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("stub"), home = root.appendingPathComponent("home")
        for folder in [bin, home.appendingPathComponent(".ssh"), root.appendingPathComponent("etc/ssh")] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        var files = machine.files
        if files["etc/ssh/sshd_config"] == nil { files["etc/ssh/sshd_config"] = "Port 22\n" }
        for (path, text) in files {
            let target = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: target, atomically: true, encoding: .utf8)
        }
        if let keys = machine.keys { try keys.write(to: home.appendingPathComponent(".ssh/authorized_keys"), atomically: true, encoding: .utf8) }
        try stub(bin, "uname", "echo Linux")
        try stub(bin, "timeout", "shift; exec \"$@\"")
        try stub(bin, "systemctl", systemctl(machine.units))
        if let listing = machine.apt { try listing.write(to: root.appendingPathComponent("apt.txt"), atomically: true, encoding: .utf8) }
        try stub(bin, "apt", machine.apt == nil ? "exit 1" : "cat '\(root.path)/apt.txt'")
        return try execute(SecurityVerifyScript.make(root: root.path), path: bin.path, home: home.path)
    }

    private func stub(_ bin: URL, _ name: String, _ body: String) throws {
        let path = bin.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }

    private func systemctl(_ units: [String: String]) -> String {
        var cases = ""
        for (name, state) in units {
            let parts = state.split(separator: " ").map(String.init)
            cases += "  \(name)) printf 'LoadState=\(parts[0])\\nActiveState=\(parts[1])\\nUnitFileState=\(parts[2])\\n' ;;\n"
        }
        return "for last; do :; done\ncase \"$last\" in\n\(cases)  *) printf 'LoadState=not-found\\nActiveState=inactive\\nUnitFileState=\\n' ;;\nesac"
    }

    private func execute(_ script: String, path: String, home: String) throws -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-s"]
        process.environment = ["PATH": path + ":/usr/bin:/bin", "HOME": home]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: text.split(separator: "\n").compactMap { line in line.split(separator: "=", maxSplits: 1).map(String.init) }.filter { $0.count == 2 }.map { ($0[0], $0[1]) })
    }

    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq0nXq8bQ1v2Wv0k7p5Zl3JdE9yQ2H4xTfN8mUoR6Kc user@laptop\n"

    func testAFreshUbuntuIsAllWarnings() throws {
        let found = try run(Machine(files: ["etc/ufw/ufw.conf": "ENABLED=no\n"], units: ["ufw.service": unit("loaded", "active", "enabled")],
                                    apt: "Listing...\nopenssl/noble-security,noble-updates 3.0.13 amd64 [upgradable from: 3.0.12]\nbash/noble-updates 5.2 amd64 [upgradable from: 5.1]\ncurl/noble-security 8.5 amd64 [upgradable from: 8.4]\n", keys: key))
        XCTAssertEqual(found["password_login"], "yes")
        XCTAssertEqual(found["ban_tool"], "not_running", "neither fail2ban nor sshguard is installed")
        XCTAssertEqual(found["firewall"], "no", "ufw.service active but ENABLED=no")
        XCTAssertEqual(found["auto_updates"], "no", "the package is not installed")
        XCTAssertEqual(found["has_key_login"], "yes")
        XCTAssertEqual(found["pending_updates"], "2")
    }

    func testAHardenedUbuntuIsAllGood() throws {
        let on = unit("loaded", "active", "enabled")
        let found = try run(Machine(files: ["etc/ufw/ufw.conf": "ENABLED=yes\n", "etc/ssh/sshd_config": "Include /etc/ssh/sshd_config.d/*.conf\n", "etc/ssh/sshd_config.d/00-metaservice-hardening.conf": "PasswordAuthentication no\n",
                                            "etc/apt/apt.conf.d/20auto-upgrades": "APT::Periodic::Update-Package-Lists \"1\";\nAPT::Periodic::Unattended-Upgrade \"1\";\n"],
                                    units: ["fail2ban.service": on, "unattended-upgrades.service": on], keys: key))
        XCTAssertEqual(found["password_login"], "no")
        XCTAssertEqual(found["ban_tool"], "running")
        XCTAssertEqual(found["firewall"], "yes")
        XCTAssertEqual(found["auto_updates"], "yes")
        XCTAssertEqual(found["pending_updates"], "0")
    }

    func testAutoUpdatesNeedTheServiceAndTheSetting() throws {
        let off = "APT::Periodic::Unattended-Upgrade \"0\";\n"
        let on = unit("loaded", "active", "enabled")
        XCTAssertEqual(try run(Machine(files: ["etc/apt/apt.conf.d/20auto-upgrades": off], units: ["unattended-upgrades.service": on]))["auto_updates"], "no")
        XCTAssertEqual(try run(Machine(units: ["unattended-upgrades.service": on]))["auto_updates"], "unknown", "service on, settings file unreadable")
        XCTAssertEqual(try run(Machine(units: ["unattended-upgrades.service": unit("loaded", "inactive", "disabled")]))["auto_updates"], "no")
        XCTAssertEqual(try run(Machine(files: ["etc/apt/apt.conf.d/20auto-upgrades": "// APT::Periodic::Unattended-Upgrade \"1\";\n"], units: ["unattended-upgrades.service": on]))["auto_updates"], "no", "a comment says nothing")
    }

    func testFirewalldAndAStoppedBanToolAndSshguard() throws {
        let on = unit("loaded", "active", "enabled")
        XCTAssertEqual(try run(Machine(units: ["firewalld.service": on]))["firewall"], "yes")
        XCTAssertEqual(try run(Machine(files: ["etc/ufw/ufw.conf": "ENABLED=no\n"], units: ["firewalld.service": on]))["firewall"], "yes", "firewalld beats ufw off")
        XCTAssertEqual(try run(Machine())["firewall"], "unknown", "no ufw.conf and no firewalld: nothing is said")
        XCTAssertEqual(try run(Machine(units: ["fail2ban.service": unit("loaded", "inactive", "disabled")]))["ban_tool"], "not_running")
        XCTAssertEqual(try run(Machine(units: ["sshguard.service": on]))["ban_tool"], "running")
    }

    func testNoKeyAndNoAptAreSaidPlainly() throws {
        XCTAssertEqual(try run(Machine(keys: "# only a comment\n"))["has_key_login"], "no")
        XCTAssertEqual(try run(Machine())["has_key_login"], "no", "no authorized_keys file")
        XCTAssertEqual(try run(Machine(apt: nil))["pending_updates"], "unknown")
    }
}
