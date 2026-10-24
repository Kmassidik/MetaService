import XCTest
@testable import RootCore

final class OffersAndWindowsTests: XCTestCase {
    private func facts(_ text: String) -> RemoteFacts { RemoteProbe.parse(text)! }
    private let head = "os=Linux\narch=aarch64\nuser=build\nram_mb=32000\nkvm=yes\ndisk_free_gb=400\nport_9101=free\n"

    private func rows(_ text: String) -> [String: Requirement] {
        Dictionary(uniqueKeysWithValues: RemoteVerify.run(facts: facts(text), fingerprint: "SHA256:a", agentBuilds: ["linux-arm64"], parentURL: "http://x:9102").requirements.map { ($0.id, $0) })
    }

    func testTheProbeReadsThePackageManager() {
        XCTAssertEqual(facts(head + "pkg=apt\nsudo=password\n").packageManager, .apt)
        XCTAssertEqual(facts(head + "pkg=dnf\n").packageManager, .dnf)
        XCTAssertNil(facts(head + "pkg=emerge\n").packageManager)
        XCTAssertTrue(RemoteProbe.script.contains("apt-get:apt"), "the probe must look for apt")
    }

    func testAptWithSudoOffersTheInstallAndSaysWhetherAPasswordIsNeeded() {
        let withPassword = rows(head + "pkg=apt\nsudo=password\n")
        XCTAssertEqual(withPassword["vm_tool"]?.install, InstallOffer(part: "vm_tool", needsPassword: true))
        XCTAssertEqual(withPassword["python"]?.install, InstallOffer(part: "python", needsPassword: true))
        XCTAssertEqual(rows(head + "pkg=apt\nsudo=passwordless\n")["vm_tool"]?.install?.needsPassword, false)
    }

    func testNoOfferWhereTheInstallIsNotBuiltOrNotPossible() {
        XCTAssertNil(rows(head + "pkg=apt\nsudo=none\n")["vm_tool"]?.install, "no sudo")
        XCTAssertNil(rows(head + "pkg=dnf\nsudo=password\n")["vm_tool"]?.install, "dnf is not built")
        XCTAssertNil(rows(head + "sudo=password\n")["vm_tool"]?.install, "unknown package manager")
        let mac = rows("os=Darwin\narch=arm64\nuser=m\nram_mb=16384\ndisk_free_gb=100\nsudo=password\nport_9101=free\n")
        XCTAssertNil(mac["vm_tool"]?.install)
        XCTAssertNil(mac["python"]?.install)
    }

    func testAPassingRowHasNoOffer() {
        XCTAssertNil(rows(head + "pkg=apt\nsudo=password\ntool=incus\ntool=python3\n")["vm_tool"]?.install)
    }

    /// "Install it for me" for qemu and the KVM module: only where the part is really missing, and only where apt and sudo are there.
    func testTheVmPackagesAreOfferedOnlyWhenKvmOrQemuIsMissing() {
        let noKvm = head.replacingOccurrences(of: "kvm=yes", with: "kvm=no")
        XCTAssertEqual(rows(noKvm + "pkg=apt\nsudo=password\n")["vm_support"]?.install, InstallOffer(part: "vm_packages", needsPassword: true))
        XCTAssertEqual(rows(head.replacingOccurrences(of: "kvm=yes", with: "kvm=yes\nqemu=no") + "pkg=apt\nsudo=passwordless\n")["vm_support"]?.install?.needsPassword, false,
                       "qemu alone is enough to offer it")
        XCTAssertNil(rows(head + "qemu=yes\npkg=apt\nsudo=password\n")["vm_support"]?.install, "nothing is missing")
        XCTAssertNil(rows(noKvm + "pkg=apt\nsudo=none\n")["vm_support"]?.install, "no sudo")
        XCTAssertNil(rows(noKvm + "pkg=dnf\nsudo=password\n")["vm_support"]?.install, "dnf is not built")
        XCTAssertNil(rows(noKvm + "pkg=apt\n")["vm_support"]?.install, "no sudo at all")
        let mac = "os=Darwin\narch=arm64\nuser=m\nram_mb=16384\ndisk_free_gb=100\nsudo=password\nport_9101=free\n"
        XCTAssertNil(rows(mac)["vm_support"]?.install, "a Mac is never asked")
    }

    func testEachPackageManagerGetsItsOwnVerifiedManualLine() {
        let expected = ["apt": "sudo apt install incus", "dnf": "sudo dnf install incus", "pacman": "sudo pacman -S incus", "zypper": "sudo zypper in incus"]
        for (manager, command) in expected { XCTAssertTrue(rows(head + "pkg=\(manager)\n")["vm_tool"]!.fix!.contains(command), manager) }
        XCTAssertTrue(rows(head + "pkg=apk\n")["vm_tool"]!.fix!.contains("rc-update add incusd"))
        XCTAssertTrue(rows(head + "pkg=dnf\n")["python"]!.fix!.contains("sudo dnf install python3"))
        XCTAssertTrue(rows(head + "pkg=pacman\n")["python"]!.fix!.contains("sudo pacman -S python"))
    }

    func testAWindowsAnswerIsOneClearCrossAndNeverAnInstall() {
        XCTAssertTrue(SshErrors.looksLikeWindows("'sh' is not recognized as an internal or external command,\r\noperable program or batch file."))
        XCTAssertTrue(SshErrors.looksLikeWindows("sh : The term 'sh' is not recognized as the name of a cmdlet, function, script file"))
        XCTAssertFalse(SshErrors.looksLikeWindows("Permission denied (publickey)."))
        let result = RemoteVerify.run(facts: RemoteProbe.windows(user: "kurnia"), fingerprint: "SHA256:a", agentBuilds: ["linux-arm64"], parentURL: "http://x:9102")
        XCTAssertFalse(result.canAdd)
        XCTAssertEqual(result.requirements.map(\.id), ["login", "system"])
        let system = result.requirements[1]
        XCTAssertFalse(system.ok)
        XCTAssertTrue(system.detail.contains("Windows is not supported yet"))
        XCTAssertNotNil(system.fix)
        XCTAssertNil(system.install)
        XCTAssertEqual(result.system, "Windows")
    }
}
