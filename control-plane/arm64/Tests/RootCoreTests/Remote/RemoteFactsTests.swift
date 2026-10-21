import XCTest
@testable import RootCore

final class RemoteFactsTests: XCTestCase {
    /// What the probe script really printed on an Apple Silicon Mac.
    private let mac = """
    os=Darwin
    arch=arm64
    user=mac
    host=Macs-Mini
    home=/Users/mac
    version=macOS 26.6.2
    chip=Apple M2 Pro
    cpu=10
    ram_mb=16384
    disk_free_gb=242
    tool=container
    tool=python3
    tool=curl
    tool=tar
    sudo=password
    port_9101=free
    """
    private let linux = """
    os=Linux
    arch=x86_64
    user=build
    home=/home/build
    version=Ubuntu 24.04.1 LTS
    chip=Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz
    cpu=8
    ram_mb=32108
    kvm=yes
    disk_free_gb=412
    tool=incus
    tool=curl
    sudo=passwordless
    port_9101=free
    """

    func testARealMacAnswerIsRead() throws {
        let facts = try XCTUnwrap(RemoteProbe.parse(mac))
        XCTAssertEqual([facts.os, facts.arch, facts.user, facts.home, facts.version, facts.chip], ["Darwin", "arm64", "mac", "/Users/mac", "macOS 26.6.2", "Apple M2 Pro"])
        XCTAssertEqual(facts.hostname, "Macs-Mini")
        XCTAssertEqual([facts.cpuCores, facts.ramMb, facts.diskFreeGb], [10, 16384, 242])
        XCTAssertEqual(facts.tools, ["container", "python3", "curl", "tar"])
        XCTAssertEqual(facts.sudo, .password)
        XCTAssertEqual(facts.port9101Free, true)
        XCTAssertTrue(facts.isMac)
        XCTAssertEqual(facts.agentBuild, "darwin-arm64")
        XCTAssertNil(facts.kvm)
    }

    func testALinuxAnswerIsRead() throws {
        let facts = try XCTUnwrap(RemoteProbe.parse(linux))
        XCTAssertEqual(facts.kvm, true)
        XCTAssertEqual(facts.sudo, .passwordless)
        XCTAssertEqual(facts.tools, ["incus", "curl"])
        XCTAssertEqual(facts.agentBuild, "linux-x86_64")
        XCTAssertEqual(RemoteProbe.parse("os=Linux\narch=aarch64\n")?.agentBuild, "linux-arm64")
    }

    func testAnswerWithoutAnOsOrAChipTypeIsUseless() {
        XCTAssertNil(RemoteProbe.parse(""))
        XCTAssertNil(RemoteProbe.parse("os=Linux\n"))
        XCTAssertNil(RemoteProbe.parse("arch=arm64\n"))
        XCTAssertNil(RemoteProbe.parse("hello\nworld\n"))
    }

    func testTextFromAnotherComputerIsCutToAShortPrintableLine() throws {
        let hostile = "os=Linux\narch=x86_64\nversion=\(String(repeating: "A", count: 500))\nchip=Bad\u{1B}[31mred\u{7}\u{0}\ntool=rm\ntool=incus\nsudo=root\nunknown=1\nram_mb=lots\n"
        let facts = try XCTUnwrap(RemoteProbe.parse(hostile))
        XCTAssertEqual(facts.version.count, 120)
        XCTAssertEqual(facts.chip, "Bad[31mred")
        XCTAssertEqual(facts.tools, ["incus"], "only the tools we look for")
        XCTAssertEqual(facts.sudo, SudoAccess.none, "an unknown sudo word counts as none")
        XCTAssertNil(facts.ramMb)
    }

    func testTheProbeOnlyReads() {
        let commands = RemoteProbe.script.split(separator: "\n").dropFirst().joined(separator: "\n")  // the first line only widens the search path
        for word in ["rm ", "mv ", "chmod", "chown", "mkdir", "touch", "tee ", ">>", "curl -", "wget", "apt install", "apt-get install", "apt-get update", "dnf install", "brew", "launchctl", "systemctl"] {
            XCTAssertFalse(commands.contains(word), "the probe must not contain \(word)")
        }
        XCTAssertFalse(commands.contains(" > "), "no redirect to a file (only to /dev/null, written without spaces)")
    }

    func testTheProbeOnlyLooksForThePackageManagerAndNeverRunsIt() {
        let line = RemoteProbe.script.split(separator: "\n").first { $0.contains("command -v \"${manager%%:*}\"") }
        XCTAssertNotNil(line, "the package manager is found with command -v only")
        XCTAssertFalse(RemoteProbe.script.contains("sudo apt"))
    }

    func testTheProbeLooksInTheUsualToolFoldersBecauseAnSshShellHasAShortPath() {
        for folder in ["/usr/local/bin", "/opt/homebrew/bin", "/snap/bin"] { XCTAssertTrue(RemoteProbe.script.contains(folder), folder) }
        XCTAssertTrue(RemoteProbe.script.hasPrefix("PATH=\"$PATH:"), "the path is widened before any tool is looked for")
    }

    func testThePortAnswerSaysWhetherTheProgramThereIsOurs() throws {
        let ours = try XCTUnwrap(RemoteProbe.parse(mac.replacingOccurrences(of: "port_9101=free", with: "port_9101=ours")))
        XCTAssertEqual([ours.port9101Free, ours.port9101Ours], [true, true])
        let other = try XCTUnwrap(RemoteProbe.parse(mac.replacingOccurrences(of: "port_9101=free", with: "port_9101=busy")))
        XCTAssertEqual([other.port9101Free, other.port9101Ours], [false, false])
    }

    func testTheProbeScriptAsksForEveryFactTheParserReads() {
        for key in ["os=", "arch=", "user=", "host=", "home=", "version=", "chip=", "cpu=", "ram_mb=", "disk_free_gb=", "kvm=", "tool=", "sudo=", "port_9101="] {
            XCTAssertTrue(RemoteProbe.script.contains("echo \"\(key)") || RemoteProbe.script.contains("echo \"\(key)"), key)
        }
    }
}
