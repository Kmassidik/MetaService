import CryptoKit
import XCTest
@testable import RootCore

/// These tests run the generated scripts for real in a throw-away home folder, and compare every file before and after.
final class PlanScriptsTests: XCTestCase {
    private var home = ""
    private let fakeProgram = "#!/bin/sh\ncase \"$1\" in\n  enroll) printf 'enrolled %s\\n' \"$*\" > \"$(dirname \"$0\")/../state/enrolled.txt\" ;;\n  run) exec sleep 60 ;;\nesac\n"

    override func setUpWithError() throws {
        home = (NSTemporaryDirectory() + "ms-plan-" + UUID().uuidString) as String
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        addTeardownBlock { [home] in
            if let pid = try? String(contentsOfFile: home + "/metaservice-box/state/agent.pid", encoding: .utf8) { _ = self.sh("kill \(pid.trimmingCharacters(in: .whitespacesAndNewlines)) 2>/dev/null") }
            try? FileManager.default.removeItem(atPath: home)
        }
    }

    private var options: RemoteInstallOptions {
        var value = RemoteInstallOptions.defaults(name: "office-mini", home: home, engine: "simulated", rootURL: "http://127.0.0.1:9102")
        value.agentPort = 9333
        return value
    }

    @discardableResult private func sh(_ script: String) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-s"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try! process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Every file, folder and its mode and content, so two states of the home folder can be compared.
    private func snapshot() -> [String: String] {
        var found: [String: String] = [:]
        for case let path as String in FileManager.default.enumerator(atPath: home)! {
            let full = home + "/" + path
            let attributes = try! FileManager.default.attributesOfItem(atPath: full)
            let mode = ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0)
            let digest = (attributes[.type] as? FileAttributeType) == .typeDirectory ? "dir" : SHA256.hash(data: FileManager.default.contents(atPath: full) ?? Data()).map { String(format: "%02x", $0) }.joined()
            found[path] = "\(String(mode, radix: 8)) \(digest)"
        }
        return found
    }

    /// What the parent does: the check, then each step's script, the program streamed in as a file.
    private func install(_ options: RemoteInstallOptions, key: String? = "ssh-ed25519 AAAAFAKEKEY somebody") throws -> (before: BeforeFactsResult, plan: InstallPlan) {
        let plan = try InstallPlan.make(options, agentSize: nil)
        let before = sh(PlanScripts.beforeScript(options))
        XCTAssertEqual(before.status, 0, before.output)
        let facts = PlanScripts.BeforeFacts.parse(before.output)
        for step in plan.steps {
            let script = try PlanScripts.script(step.operations, enrollToken: "one-time-token", keyLine: key.map { PlanScripts.keyLine(publicKey: $0, options: options) },
                                                manifest: PlanScripts.manifest(options, createdAt: "2026-10-12T00:00:00Z", before: facts))
            let done = sh(script)
            XCTAssertEqual(done.status, 0, "\(step.id): \(done.output)")
            if step.id == "folder" { try putProgram(options) }
        }
        return (BeforeFactsResult(facts: facts), plan)
    }

    struct BeforeFactsResult { let facts: PlanScripts.BeforeFacts }

    private func putProgram(_ options: RemoteInstallOptions) throws {
        let path = options.box + "/bin/" + InstallPlan.programName
        try fakeProgram.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    }

    func testTheWholeInstallRunsForRealAndOnlyAddsTheBoxAndOneKeyLine() throws {
        try FileManager.default.createDirectory(atPath: home + "/.ssh", withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try "ssh-ed25519 AAAAEXISTING me@laptop\n".write(toFile: home + "/.ssh/authorized_keys", atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: home + "/.ssh/authorized_keys")
        let untouched = snapshot()
        let installed = try install(options)
        let after = snapshot()
        XCTAssertEqual(Set(after.keys).subtracting(untouched.keys), Set(["metaservice-box", "metaservice-box/bin", "metaservice-box/bin/metaservice-agent", "metaservice-box/logs", "metaservice-box/logs/agent.log",
                                                                           "metaservice-box/manifest.json", "metaservice-box/start.sh", "metaservice-box/state", "metaservice-box/state/agent.pid",
                                                                           "metaservice-box/state/enrolled.txt", "metaservice-box/stop.sh"]), "only the box is new")
        let changed = untouched.keys.filter { untouched[$0] != after[$0] }
        XCTAssertEqual(changed, [".ssh/authorized_keys"], "the only existing file that changes is authorized_keys")
        let keys = try String(contentsOfFile: home + "/.ssh/authorized_keys", encoding: .utf8)
        XCTAssertTrue(keys.hasPrefix("ssh-ed25519 AAAAEXISTING me@laptop\n"), "the user's own line is untouched")
        XCTAssertEqual(keys.split(separator: "\n").count, 2)
        XCTAssertTrue(keys.hasSuffix("metaservice-office-mini\n"))
        XCTAssertNil(try? FileManager.default.attributesOfItem(atPath: home + "/metaservice-box/state/enroll.token"), "the one-time token is gone")
        XCTAssertEqual(try String(contentsOfFile: home + "/metaservice-box/state/enrolled.txt", encoding: .utf8).contains("--name office-mini"), true)
        XCTAssertEqual(installed.plan.options.box, home + "/metaservice-box")
    }

    func testAHalfInstalledBoxCanBeRolledBackButAnUnmarkedFolderCannot() throws {
        let plan = try InstallPlan.make(options, agentSize: nil)
        XCTAssertEqual(sh(PlanScripts.beforeScript(options)).status, 0)
        let folder = try XCTUnwrap(plan.steps.first { $0.id == "folder" })
        XCTAssertEqual(sh(try PlanScripts.script(folder.operations)).status, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: options.box + "/.partial"))
        XCTAssertEqual(sh(PlanScripts.removeScript(box: options.box, key: nil)).status, 30, "a normal removal refuses a box without its record")
        XCTAssertEqual(sh(PlanScripts.removeScript(box: options.box, key: nil, rollingBack: true)).status, 0)
        XCTAssertEqual(snapshot(), [:], "everything the failed install made is gone")
        try FileManager.default.createDirectory(atPath: options.box, withIntermediateDirectories: false)
        XCTAssertEqual(sh(PlanScripts.removeScript(box: options.box, key: nil, rollingBack: true)).status, 30, "a folder with no marker is never ours")
    }

    /// Removing a machine must take its containers and VMs with it: left behind they keep running, using memory and disk, with
    /// nothing in the panel able to see them.
    func testRemovalDeletesTheWorkloadsThatMachineMade() {
        let script = PlanScripts.removeScript(box: options.box, key: nil)
        for part in ["incus delete --force \"$instance\"", "delete --force \"$instance\"", "grep '^ms-'", "grep -o '\"name\":\"ms-", "ms-note: could not delete"] {
            XCTAssertTrue(script.contains(part), part)
        }
        XCTAssertFalse(script.contains("incus delete --force all"), "only the names the helper made, never everything")
        XCTAssertEqual(script, PlanScripts.removeScript(box: options.box, key: nil), "the script is fixed text")
    }

    /// The boot registration goes with the box, and before `stop.sh`: launchd or systemd would start the program again seconds after it was stopped, with no
    /// folder and nothing in the panel able to see it. The helper's LaunchAgent is the login's own file and needs no sudo; the jobs of the earlier system-domain
    /// design may still be there and go too. `sudo -n` only, so a removal never waits for a password.
    func testRemovalAlsoTakesTheBootRegistrationAway() throws {
        let script = PlanScripts.removeScript(box: options.box, key: nil)
        for part in ["launchctl bootout gui/$(id -u)/\(AutostartScript.label)", "rm -f \"\(AutostartScript.macPath)\"",
                     "launchctl bootout system/\(AutostartScript.label)", "sudo -n rm -f \(AutostartScript.legacyDaemonPath)",
                     "launchctl bootout system/\(AutostartScript.legacyContainerStartLabel)", "sudo -n rm -f \(AutostartScript.legacyContainerStartPath)",
                     "systemctl disable --now \(AutostartScript.unitName)", "sudo -n rm -f \(AutostartScript.linuxPath)", "systemctl daemon-reload"] {
            XCTAssertTrue(script.contains(part), part)
        }
        for line in script.split(separator: "\n") where line.contains("gui/") {
            XCTAssertFalse(line.contains("sudo"), "the login's own job is stopped without sudo: \(line)")
        }
        XCTAssertFalse(script.contains("sudo -S"), "a removal never asks for a password")
        let registration = try XCTUnwrap(script.range(of: "launchctl bootout"))
        let stop = try XCTUnwrap(script.range(of: "stop.sh"))
        XCTAssertLessThan(registration.lowerBound, stop.lowerBound, "the service is unregistered before the program is stopped")
    }

    func testTheProgramStartsFromTheBoxAndStopsAgain() throws {
        var withoutKey = options
        withoutKey.installKey = false
        _ = try install(withoutKey, key: nil)
        let pid = try String(contentsOfFile: home + "/metaservice-box/state/agent.pid", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(sh("kill -0 \(pid) && echo alive").output.trimmingCharacters(in: .whitespacesAndNewlines), "alive")
        XCTAssertEqual(sh("sh \(Shell.quote(home + "/metaservice-box/start.sh"))").output.trimmingCharacters(in: .whitespacesAndNewlines), "already running")
        sh("sh \(Shell.quote(home + "/metaservice-box/stop.sh"))")
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertNotEqual(sh("kill -0 \(pid) 2>/dev/null && echo alive || echo gone").output.trimmingCharacters(in: .whitespacesAndNewlines), "alive")
    }

    func testRemovingTheBoxLeavesTheHomeFolderExactlyAsItWas() throws {
        try FileManager.default.createDirectory(atPath: home + "/.ssh", withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try "ssh-ed25519 AAAAEXISTING me@laptop\n\nssh-rsa AAAAOTHER other\n".write(toFile: home + "/.ssh/authorized_keys", atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: home + "/.ssh/authorized_keys")
        try "my notes".write(toFile: home + "/notes.txt", atomically: true, encoding: .utf8)
        let original = snapshot()
        let installed = try install(options)
        let facts = installed.before.facts
        let key = PlanScripts.RemovedKey(file: home + "/.ssh/authorized_keys", marker: PlanScripts.keyMarker("office-mini"), fileCreated: !facts.keyFileExisted, directoryCreated: !facts.sshDirExisted)
        let removed = sh(PlanScripts.removeScript(box: options.box, key: key))
        XCTAssertEqual(removed.status, 0, removed.output)
        XCTAssertEqual(snapshot(), original, "after removal the home folder is byte for byte as it was")
    }

    func testWhenTheSshFolderDidNotExistRemovalTakesWhatTheInstallMadeAway() throws {
        let original = snapshot()
        let installed = try install(options)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home + "/.ssh/authorized_keys"))
        let facts = installed.before.facts
        XCTAssertEqual([facts.sshDirExisted, facts.keyFileExisted], [false, false])
        let key = PlanScripts.RemovedKey(file: home + "/.ssh/authorized_keys", marker: PlanScripts.keyMarker("office-mini"), fileCreated: true, directoryCreated: true)
        XCTAssertEqual(sh(PlanScripts.removeScript(box: options.box, key: key)).status, 0)
        XCTAssertEqual(snapshot(), original)
    }

    func testAnExistingFolderIsNeverTouched() throws {
        try FileManager.default.createDirectory(atPath: home + "/metaservice-box", withIntermediateDirectories: false)
        try "precious".write(toFile: home + "/metaservice-box/mine.txt", atomically: true, encoding: .utf8)
        let before = snapshot()
        let result = sh(PlanScripts.beforeScript(options))
        XCTAssertEqual(result.status, 20)
        XCTAssertTrue(result.output.contains("already exists"))
        XCTAssertEqual(snapshot(), before)
    }

    func testRemovalRefusesAFolderThatIsNotAMetaServiceBox() throws {
        try FileManager.default.createDirectory(atPath: home + "/metaservice-box", withIntermediateDirectories: false)
        try "precious".write(toFile: home + "/metaservice-box/mine.txt", atomically: true, encoding: .utf8)
        let before = snapshot()
        let result = sh(PlanScripts.removeScript(box: options.box, key: nil))
        XCTAssertEqual(result.status, 30)
        XCTAssertEqual(snapshot(), before, "nothing was removed")
        try "{\"made_by\":\"someone else\"}".write(toFile: home + "/metaservice-box/manifest.json", atomically: true, encoding: .utf8)
        XCTAssertEqual(sh(PlanScripts.removeScript(box: options.box, key: nil)).status, 30)
    }

    func testTheKeyLineCanOnlyForwardTheAgentsPort() {
        let line = PlanScripts.keyLine(publicKey: "ssh-ed25519 AAAAKEY comment-to-drop", options: options)
        XCTAssertEqual(line, "restrict,port-forwarding,permitopen=\"127.0.0.1:9333\",command=\"exit 1\" ssh-ed25519 AAAAKEY metaservice-office-mini")
        XCTAssertFalse(line.contains("comment-to-drop"))
    }

    func testTheKeyLineAlsoAllowsListeningForTheWayBackToTheParentWhenThereIsOne() {
        var withReturn = options
        withReturn.reversePort = 9102
        let line = PlanScripts.keyLine(publicKey: "ssh-ed25519 AAAAKEY", options: withReturn)
        XCTAssertEqual(line, "restrict,port-forwarding,permitopen=\"127.0.0.1:9333\",permitlisten=\"127.0.0.1:9102\",command=\"exit 1\" ssh-ed25519 AAAAKEY metaservice-office-mini")
    }

    func testTheManifestIsCompactSortedAndHoldsNoSecret() {
        let text = PlanScripts.manifest(options, createdAt: "2026-10-12T00:00:00Z", before: .init(sshDirExisted: true, keyFileExisted: false))
        XCTAssertTrue(text.hasPrefix("{\"agent_port\":9333,\"box\":"))
        XCTAssertTrue(text.contains("\"made_by\":\"metaservice\""))
        XCTAssertTrue(text.contains("\"key_file_created\":true") && text.contains("\"ssh_dir_created\":false"))
        XCTAssertFalse(text.lowercased().contains("token") || text.lowercased().contains("password"))
        XCTAssertFalse(text.contains("\n"))
    }

    func testAScriptWithoutWhatItNeedsIsRefusedAndContentCannotEndTheHeredoc() throws {
        let plan = try InstallPlan.make(options, agentSize: nil)
        let enroll = try XCTUnwrap(plan.steps.first { $0.id == "enroll" })
        XCTAssertThrowsError(try PlanScripts.script(enroll.operations)) { XCTAssertEqual($0 as? PlanScriptError, .missing("the enrollment token")) }
        XCTAssertThrowsError(try PlanScripts.script([.putFile(path: "/x/y", mode: "600", source: .text("a\n__METASERVICE_END__\nrm -rf /"))])) { XCTAssertEqual($0 as? PlanScriptError, .unsafeContent) }
        XCTAssertThrowsError(try PlanScripts.script([.addKeyLine(file: "/x/y")])) { XCTAssertEqual($0 as? PlanScriptError, .missing("the key line")) }
        XCTAssertThrowsError(try PlanScripts.script([.addKeyLine(file: "/x/y")], keyLine: "a\nb"))
    }

    func testTheProgramsOwnCommandLinesHaveTheLimitsAndStayOnLoopback() {
        var value = options
        value.settings = MachineSettings(ramReserveMb: 4096, diskReserveGb: 30, ramAllowanceMb: 12288, diskAllowanceGb: 400)
        let arguments = PlanScripts.runArguments(value)
        XCTAssertEqual(Array(arguments.prefix(1)), ["run"])
        for pair in [["--bind", "127.0.0.1"], ["--chat-bind", "127.0.0.1"], ["--port", "9333"], ["--chat-port", "9432"], ["--engine", "simulated"], ["--ram-reserve-mb", "4096"], ["--disk-allowance-gb", "400"]] {
            let index = arguments.firstIndex(of: pair[0])
            XCTAssertNotNil(index, pair[0])
            XCTAssertEqual(index.map { arguments[$0 + 1] }, pair[1])
        }
        XCTAssertTrue(PlanScripts.startScript(value).contains("'--state-dir' 'state'"), "start.sh uses paths inside the box")
        XCTAssertFalse(PlanScripts.startScript(value).contains(home), "start.sh keeps working if the folder is moved")
    }

    private func runBeforeScript(box: String, manifest: String?) throws -> (status: Int32, output: String) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ms-before-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let boxPath = folder.appendingPathComponent(box).path
        try FileManager.default.createDirectory(atPath: boxPath, withIntermediateDirectories: true)
        if let manifest { try manifest.write(toFile: boxPath + "/manifest.json", atomically: true, encoding: .utf8) }
        var options = RemoteInstallOptions.defaults(name: "office-mini", home: folder.path, engine: "apple", rootURL: "http://192.168.100.40:9102")
        options.box = boxPath
        options.sshDirectory = folder.path + "/.ssh"
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", PlanScripts.beforeScript(options)]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func testABoxFromAnEarlierInstallOfOursIsReportedNotRefused() throws {
        let result = try runBeforeScript(box: "box", manifest: "{\"made_by\":\"metaservice\"}")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(PlanScripts.BeforeFacts.parse(result.output).earlierBoxIsOurs)
    }

    func testAFolderThatIsNotOursIsStillRefused() throws {
        for manifest in [nil, "{\"made_by\":\"someone else\"}"] {
            let result = try runBeforeScript(box: "box", manifest: manifest)
            XCTAssertEqual(result.status, 20)
            XCTAssertTrue(result.output.contains("not a MetaService box"))
        }
    }
}
