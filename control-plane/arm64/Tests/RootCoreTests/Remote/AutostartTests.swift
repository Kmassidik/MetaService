import XCTest
@testable import RootCore

/// The "Starts at boot" row: it exists only for a computer that already has a box of ours, it warns instead of stopping anything, and it offers the registration
/// only where it can be written.
final class AutostartTests: XCTestCase {
    private let mac = "os=Darwin\narch=arm64\nuser=mac\nhome=/Users/mac\nversion=macOS 26\nchip=Apple M2\nram_mb=16384\ndisk_free_gb=242\ntool=container\ntool=python3\nsudo=password\nport_9101=free\n"
    private let linux = "os=Linux\narch=x86_64\nuser=build\nhome=/home/build\nversion=Ubuntu 24.04\nram_mb=32000\nkvm=yes\nqemu=yes\ndisk_free_gb=400\ntool=incus\ntool=python3\npkg=apt\nsudo=password\nport_9101=free\n"

    private func check(_ text: String) -> RemoteVerification {
        RemoteVerify.run(facts: RemoteProbe.parse(text)!, fingerprint: "SHA256:a", agentBuilds: ["darwin-arm64", "linux-x86_64"], parentURL: "http://x:9102")
    }

    private func row(_ text: String) -> Requirement? { check(text).requirements.first { $0.id == Autostart.rowId } }

    /// The check only answers when a box of ours is there, so a computer being added has nothing to be told about its boot service.
    func testAComputerThatDidNotAnswerHasNoRowAtAll() {
        XCTAssertNil(RemoteProbe.parse(mac)!.autostart)
        XCTAssertNil(row(mac))
        XCTAssertNil(row(linux))
    }

    func testARegisteredHelperIsAPlainTick() {
        let registered = row(linux + "autostart=yes\n")!
        XCTAssertTrue(registered.ok)
        XCTAssertEqual(registered.label, "Starts at boot")
        XCTAssertEqual(registered.detail, Autostart.registeredDetail)
        XCTAssertNil(registered.fix)
        XCTAssertNil(registered.install)
        XCTAssertEqual(RemoteVerify.optionalRows.contains(Autostart.rowId), true, "the panel may warn about it, but it never blocks adding a computer")
    }

    func testAnUnregisteredHelperSaysItShowsOfflineAndOffersTheInstall() {
        let missing = row(linux + "autostart=no\n")!
        XCTAssertEqual(missing.detail, "This computer's helper is not registered to start at boot, so it shows offline after a restart.")
        XCTAssertEqual(missing.install, InstallOffer(part: "autostart", needsPassword: true))
        XCTAssertTrue(missing.fix!.contains("start.sh"), missing.fix!)
        XCTAssertTrue(check(linux + "autostart=no\n").canAdd, "a machine that works is never stopped by this row")
    }

    /// A Mac is allowed, because this part is a file for launchd and not a package; everything else still waits for apt and sudo.
    func testAMacAndALinuxComputerWithAptAreOfferedItAndNothingElseIs() {
        XCTAssertEqual(row(mac + "autostart=no\n")?.install, InstallOffer(part: "autostart", needsPassword: true))
        XCTAssertEqual(row(mac.replacingOccurrences(of: "sudo=password", with: "sudo=passwordless") + "autostart=no\n")?.install?.needsPassword, false)
        XCTAssertNil(row(mac.replacingOccurrences(of: "sudo=password", with: "sudo=none") + "autostart=no\n")?.install, "a login without sudo cannot write it")
        XCTAssertNil(row(linux.replacingOccurrences(of: "pkg=apt", with: "pkg=dnf") + "autostart=no\n")?.install, "dnf is not built")
        XCTAssertNil(row(linux.replacingOccurrences(of: "home=/home/build\n", with: "") + "autostart=no\n")?.install, "a box path this parent cannot write is never offered")
    }
}
