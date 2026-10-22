import XCTest
import MSCore
@testable import AgentCore

/// `install_sshd` on top of the SSH keys call: the fixed script, its report, the request flag, the failure answers and the order of the two calls.
/// The script is also run once under a throwaway root (every path rewritten into a temp folder, a stub `sshd`), so its config logic is exercised without touching a real system.
final class SshdInstallScriptTests: XCTestCase {
    /// What the plain (no install) script was before this feature; it must not change by a byte.
    private let plainScript = """
    set -e
    umask 077
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    cat > /root/.ssh/authorized_keys.new
    chmod 600 /root/.ssh/authorized_keys.new
    mv -f /root/.ssh/authorized_keys.new /root/.ssh/authorized_keys
    if cat /proc/[0-9]*/comm 2>/dev/null | grep -qx sshd; then
      echo sshd=running
    elif command -v sshd >/dev/null 2>&1 || [ -x /usr/sbin/sshd ]; then
      echo sshd=installed
    else
      echo sshd=missing
    fi
    """

    private func position(_ needle: String) throws -> String.Index {
        try XCTUnwrap(SshdInstallScript.text.range(of: needle), "the install script has no \(needle)").lowerBound
    }

    func testThePlainScriptIsUnchangedByteForByte() {
        XCTAssertEqual(SshKeysScript.text, plainScript)
    }

    func testTheInstallScriptIsValidShellText() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", "-c", SshdInstallScript.text]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testTheArgumentsAreAFixedExecOfTheConstantWithNoRequestData() {
        let args = SshdInstallScript.arguments(id: "w-abc")
        XCTAssertEqual(args, ["exec", "ms-w-abc", "/bin/sh", "-c", SshdInstallScript.text], "no -i: nothing goes on standard input")
        XCTAssertEqual(SshdInstallScript.arguments(id: "w-zzz").last, args.last)
        XCTAssertFalse(SshdInstallScript.text.contains("authorized_keys") || SshdInstallScript.text.contains("ssh-ed25519"), "no key handling in the install script")
    }

    func testTheConfigIsExactlyTheFourKeyOnlyLinesInADropIn() throws {
        let four = "PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\nPubkeyAuthentication yes\nEOF"
        XCTAssertTrue(SshdInstallScript.text.contains(four), "the four lines, in this order, and nothing else")
        for line in ["PasswordAuthentication no\n", "KbdInteractiveAuthentication no\n", "PermitRootLogin prohibit-password\n", "PubkeyAuthentication yes\n"] {
            XCTAssertEqual(SshdInstallScript.text.components(separatedBy: line).count - 1, 1, line)
        }
        for needle in ["/etc/ssh/sshd_config.d/10-metaservice.conf", "# BEGIN metaservice", "# END metaservice", "Include", "sshd -t"] {
            XCTAssertTrue(SshdInstallScript.text.contains(needle), needle)
        }
    }

    func testPackageManagersAreTriedInOrderAndOnlyTheInstallScriptInstalls() throws {
        let order = try ["command -v apt-get", "command -v apk", "command -v dnf", "command -v yum"].map(position)
        XCTAssertEqual(order, order.sorted())
        for command in ["DEBIAN_FRONTEND=noninteractive apt-get update", "DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server", "apk add --no-cache openssh",
                        "dnf -y install openssh-server", "yum -y install openssh-server"] {
            XCTAssertTrue(SshdInstallScript.text.contains(command), command)
        }
        for word in ["apt-get", "apk add", "dnf", "yum", "systemctl", "ssh-keygen"] {
            XCTAssertFalse(SshKeysScript.text.contains(word), "the keys script must not touch \(word)")
        }
    }

    func testItNamesEveryFailureAndStartsTheServerBySystemdOrPlainly() throws {
        for failure in [SshdFailure.noPackageManager, .installFailed, .configInvalid, .notListening] {
            XCTAssertTrue(SshdInstallScript.text.contains(failure.rawValue), failure.rawValue)
        }
        for needle in ["systemctl enable --now", "systemctl reload", "/run/systemd/system", "kill -HUP", "ssh-keygen -A", "mkdir -p /run/sshd", "/proc/net/tcp6", ":0016"] {
            XCTAssertTrue(SshdInstallScript.text.contains(needle), needle)
        }
        XCTAssertLessThan(try position("has_sshd || ensure_package"), try position("apply_config\nstart_server"), "install before config before start")
    }

    func testTheReportIsReadAndNothingIsGuessed() {
        XCTAssertEqual(SshdInstallScript.parseReport("sshd=running\ninstalled=true\n"), SshdInstallReport(sshd: .running, installed: true, failure: nil))
        XCTAssertEqual(SshdInstallScript.parseReport("apt noise\nsshd=installed\ninstalled=false\nfailure=not_listening\n")?.failure, .notListening)
        XCTAssertEqual(SshdInstallScript.parseReport("sshd=missing\n")?.installed, false, "no installed line means not installed")
        for bad in ["", "installed=true\n", "sshd=maybe\n", "sshd=running\nfailure=oops\n"] {
            XCTAssertNil(SshdInstallScript.parseReport(bad), bad.debugDescription)
        }
    }

    func testEveryFailureHasItsPlainMessage() {
        XCTAssertEqual(SshdFailure.noPackageManager.message, "The VM has no package manager the helper knows (apt, apk, dnf, yum), so it cannot install the SSH server.")
        XCTAssertEqual(SshdFailure.installFailed.message, "The VM could not download the SSH server. Check that the VM has internet access.")
        XCTAssertEqual(SshdFailure.configInvalid.message, "The SSH server did not accept its settings, so nothing was changed.")
        XCTAssertEqual(SshdFailure.notListening.message, "The SSH server was installed but is not listening on port 22.")
        XCTAssertEqual(SshdFailure.errorCode, "sshd_install_failed")
    }

    func testAFailedOrTimedOutRunOrAMissingReportIsInstallFailed() async {
        do {
            _ = try await SshdInstallScript.install(id: "w-1") { _ in throw EngineError.failed("container exec took too long") }
            XCTFail("a failed exec must fail")
        } catch { XCTAssertEqual(error as? SshdFailure, .installFailed) }
        do {
            _ = try await SshdInstallScript.install(id: "w-1") { _ in "garbage" }
            XCTFail("no report must fail")
        } catch { XCTAssertEqual(error as? SshdFailure, .installFailed) }
        let report = try? await SshdInstallScript.install(id: "w-1") { _ in "sshd=running\ninstalled=true\n" }
        XCTAssertEqual(report, SshdInstallReport(sshd: .running, installed: true, failure: nil))
    }
}

final class SshdInstallRequestTests: XCTestCase {
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE01 alice@laptop"

    private func body(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    func testInstallSshdIsABooleanThatDefaultsToFalse() throws {
        XCTAssertFalse(try SshKeysRequest(body: body(["keys": [key]])).installSshd)
        XCTAssertTrue(try SshKeysRequest(body: body(["keys": [key], "install_sshd": true])).installSshd)
        XCTAssertFalse(try SshKeysRequest(body: body(["keys": [key], "install_sshd": false])).installSshd)
        for wrong: Any in ["yes", 1, NSNull(), ["true"]] {
            XCTAssertThrowsError(try SshKeysRequest(body: body(["keys": [key], "install_sshd": wrong])), "\(wrong)")
        }
        XCTAssertThrowsError(try SshKeysRequest(body: body(["keys": [key], "install": true])), "other unknown fields stay refused")
    }

    func testTheResultEncodesInstalledOnlyWhenAsked() throws {
        func json(_ result: SshKeysResult) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        }
        let asked = try json(SshKeysResult(applied: 1, sshd: .running, installed: true))
        XCTAssertEqual(asked["installed"] as? Bool, true)
        XCTAssertEqual(asked["sshd"] as? String, "running")
        XCTAssertNil(try json(SshKeysResult(applied: 1, sshd: .running))["installed"])
    }
}

final class SshdInstallServiceTests: XCTestCase {
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE01 alice@laptop"
    private let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, ramTotalMb: 32768, diskTotalGb: 500, gpu: [])

    private func machine() async throws -> (AgentService, SimulatedEngine) {
        let engine = SimulatedEngine()
        let request = try CreateWorkloadRequest(body: JSONSerialization.data(withJSONObject: ["command_id": "c-1", "name": "demo", "kind": "vm", "cpu": 1, "ram_mb": 1024, "disk_gb": 5]))
        _ = try await engine.create(id: "w-1", request: request)
        return (AgentService(engine: engine, budget: SpaceBudget(ramTotalMb: 32768, diskTotalGb: 1000), specs: specs, agentVersion: "0.9.9"), engine)
    }

    func testAMissingSshdIsInstalledOnceAndTheSecondCallInstallsNothing() async throws {
        let (service, _) = try await machine()
        let first = try await service.applySshKeys(id: "w-1", keys: [key], installSshd: true)
        XCTAssertEqual(first, SshKeysResult(applied: 1, sshd: .running, installed: true))
        let second = try await service.applySshKeys(id: "w-1", keys: [key], installSshd: true)
        XCTAssertEqual(second, SshKeysResult(applied: 1, sshd: .running, installed: false))
    }

    func testThePlainCallNeverAsksForAnInstall() async throws {
        let (service, engine) = try await machine()
        let done = try await service.applySshKeys(id: "w-1", keys: [key])
        XCTAssertEqual(done, SshKeysResult(applied: 1, sshd: .missing))
        let runs = await engine.sshInstallRuns
        XCTAssertTrue(runs.isEmpty)
    }

    func testAFailedInstallThrowsThePlainFailureAndTheKeysAreStillWritten() async throws {
        let (service, engine) = try await machine()
        for failure in [SshdFailure.noPackageManager, .installFailed, .configInvalid, .notListening] {
            await engine.failSshdInstalls(failure)
            do {
                _ = try await service.applySshKeys(id: "w-1", keys: [key], installSshd: true)
                XCTFail("an install that fails must throw")
            } catch { XCTAssertEqual(error as? SshdFailure, failure) }
            let stored = await engine.sshKeys["w-1"]
            XCTAssertEqual(stored, [key])
        }
    }

    func testTheKeysAreWrittenBeforeTheInstallAndNoKeyIsInEitherCommandLine() async throws {
        let (service, engine) = try await machine()
        _ = try await service.applySshKeys(id: "w-1", keys: [key], installSshd: true)
        let keyRuns = await engine.sshRuns
        let installRuns = await engine.sshInstallRuns
        XCTAssertEqual(keyRuns.map(\.arguments), [SshKeysScript.arguments(id: "w-1")])
        XCTAssertEqual(installRuns, [SshdInstallScript.arguments(id: "w-1")])
        XCTAssertFalse((keyRuns.map(\.arguments) + installRuns).joined().joined(separator: " ").contains("alice@laptop"))
    }

    func testTheUnavailableEngineHasNoVmsToInstallIn() async {
        let engine = UnavailableEngine(name: "apple-container", problem: HostProblem(code: "x", message: "m", fix: "f"))
        do { _ = try await engine.installSshd(id: "w-1"); XCTFail("unavailable") } catch { XCTAssertEqual(error as? EngineError, .notFound) }
    }
}

/// The install script run by the Mac's own `/bin/sh` under a throwaway root: every path is rewritten into a temp folder and `sshd` is a stub.
final class SshdInstallSandboxTests: XCTestCase {
    private var root = ""
    private let dropIn = "etc/ssh/sshd_config.d/10-metaservice.conf"
    private let main = "etc/ssh/sshd_config"
    private let fourLines = "PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\nPubkeyAuthentication yes\n"

    override func tearDown() { try? FileManager.default.removeItem(atPath: root) }

    private func box(sshdExit: Int, config: String, include: Bool) throws {
        root = NSTemporaryDirectory() + "ms-sshd-box-\(UUID().uuidString)"
        let manager = FileManager.default
        try manager.createDirectory(atPath: root + "/bin", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/etc/ssh", withIntermediateDirectories: true)
        try "#!/bin/sh\nexit \(sshdExit)\n".write(toFile: root + "/bin/sshd", atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root + "/bin/sshd")
        try ((include ? "Include \(root)/etc/ssh/sshd_config.d/*.conf\n" : "") + config).write(toFile: root + "/" + main, atomically: true, encoding: .utf8)
    }

    private func rewrittenScript() -> String {
        let script = SshdInstallScript.text
            .replacingOccurrences(of: "/etc/ssh", with: root + "/etc/ssh")
            .replacingOccurrences(of: "/run/", with: root + "/run/")
            .replacingOccurrences(of: "/usr/sbin/sshd", with: root + "/bin/sshd")
            .replacingOccurrences(of: "ssh-keygen -A </dev/null >/dev/null 2>&1", with: "true")
            .replacingOccurrences(of: "WAIT_TRIES=10", with: "WAIT_TRIES=0")
        for path in ["/etc/ssh", "/run/", "/usr/sbin/sshd"] {
            XCTAssertEqual(script.components(separatedBy: path).count, script.components(separatedBy: root + path).count, "\(path) escaped the sandbox")
        }
        XCTAssertFalse(script.contains("ssh-keygen -A"), "host keys would be made for real")
        return script
    }

    @discardableResult
    private func runScript() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", rewrittenScript()]
        process.environment = ["PATH": root + "/bin:/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func read(_ relative: String) -> String? { try? String(contentsOfFile: root + "/" + relative, encoding: .utf8) }

    func testWithAnIncludeLineOnlyTheDropInIsWrittenAndASecondRunChangesNothing() throws {
        try box(sshdExit: 0, config: "PasswordAuthentication yes\n", include: true)
        let before = try XCTUnwrap(read(main))
        XCTAssertTrue(try runScript().contains("installed=false"))
        XCTAssertEqual(read(dropIn), fourLines)
        XCTAssertEqual(read(main), before, "the main file is left alone when it includes the drop-in folder")
        try runScript()
        XCTAssertEqual(read(dropIn), fourLines)
        XCTAssertEqual(read(main), before)
    }

    func testWithoutAnIncludeLineAMarkedBlockIsAddedOnceAtTheTop() throws {
        try box(sshdExit: 0, config: "Port 22\nPasswordAuthentication yes\n", include: false)
        try runScript()
        let first = read(main)
        XCTAssertEqual(first, "# BEGIN metaservice\n\(fourLines)# END metaservice\nPort 22\nPasswordAuthentication yes\n")
        try runScript()
        XCTAssertEqual(read(main), first, "a second run does not duplicate the block")
    }

    func testAConfigSshdRefusesIsRolledBackAndReportedAsConfigInvalid() throws {
        try box(sshdExit: 1, config: "Port 22\n", include: false)
        XCTAssertTrue(try runScript().contains("failure=config_invalid"))
        XCTAssertEqual(read(main), "Port 22\n", "the previous file is back")
        XCTAssertNil(read(dropIn), "the new drop-in is removed")
    }
}
