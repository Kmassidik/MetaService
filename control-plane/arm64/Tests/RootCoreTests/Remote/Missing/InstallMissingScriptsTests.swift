import XCTest
@testable import RootCore

final class InstallMissingScriptsTests: XCTestCase {
    func testTheSudoCommandNeverHoldsAPasswordAndTheScriptIsOneQuotedArgument() {
        let command = InstallMissingScripts.sudoCommand(script: "echo 'hi'", withPassword: true)
        XCTAssertEqual(command, "LC_ALL=C LANGUAGE=C sudo -S -p '' -- sh -c 'echo '\\''hi'\\'''")
        XCTAssertTrue(InstallMissingScripts.sudoCommand(script: "true", withPassword: false).contains("sudo -n -p ''"))
    }

    func testTheIncusScriptInstallsInitialisesOnlyWhenNeededAndAddsTheUserToTheAdminGroup() {
        let script = InstallMissingScripts.script(for: .vmTool, user: "build")
        for part in ["DEBIAN_FRONTEND=noninteractive", "apt-get -y", "aptget install incus", "incus admin init --minimal", "profile device list default", "usermod -a -G incus-admin 'build'", "ms-done"] {
            XCTAssertTrue(script.contains(part), part)
        }
        XCTAssertTrue(script.contains("if ! incus profile device list default"), "init only when the server is not set up yet")
        XCTAssertTrue(script.contains("Candidate:"), "a system without an Incus package is told so before anything is installed")
    }

    func testThePythonScriptInstallsPython3() {
        let script = InstallMissingScripts.script(for: .python, user: "build")
        XCTAssertTrue(script.contains("aptget install python3"))
        XCTAssertFalse(script.contains("incus"))
    }

    /// The packages Debian and Ubuntu provide for qemu, and both KVM modules: the one for another chip fails harmlessly and is ignored.
    func testTheVmPackagesScriptIsFixedTextAndNamesThePackagesAndModules() {
        let script = InstallMissingScripts.script(for: .vmPackages, user: "build")
        XCTAssertEqual(script, InstallMissingScripts.script(for: .vmPackages, user: "someone-else"), "the script holds nothing from the request")
        for part in ["qemu-system-x86", "qemu-system-arm", "qemu-utils", "qemu-system-modules-spice", "ovmf", "qemu-efi-aarch64", "apt-get -y", "for module in kvm_amd kvm_intel", "modprobe \"$module\"", "[ -e /dev/kvm ]", InstallMissingScripts.doneMarker] {
            XCTAssertTrue(script.contains(part), part)
        }
        XCTAssertFalse(script.contains("kvm_amd kvm_intel\n"), "the modules are tried one by one, not as one name")
    }

    func testAUserNameIsQuotedInTheScript() {
        XCTAssertTrue(InstallMissingScripts.script(for: .vmTool, user: "a$b").contains("'a$b'"))
    }

    func testTheScriptIsAcceptedByTheShell() throws {
        for part in MissingPart.allCases {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-n", "-c", InstallMissingScripts.script(for: part, user: "build")]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "\(part) must be valid shell")
        }
    }
}
