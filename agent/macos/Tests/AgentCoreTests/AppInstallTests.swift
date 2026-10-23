import XCTest
import MSCore
@testable import AgentCore

/// The pure parts of the app installs: the two constant scripts, the request body, the result lines and the log tail.
final class AppInstallPureTests: XCTestCase {
    private let sha = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    private let marker = AppInstallScripts.resultMarker

    private func afterMarker(_ lines: [String]) -> String { "noise\n\(marker)\n" + lines.joined(separator: "\n") + "\n" }

    private func bash(_ script: String, flags: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = flags + ["-c", script]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: scripts

    func testBothScriptsAreValidBashText() throws {
        for kind in AppKind.allCases { XCTAssertEqual(try bash(kind.script, flags: ["-n"]), 0, kind.rawValue) }
    }

    func testTheUrlsAreExactlyTheTwoVendorInstallers() {
        XCTAssertTrue(AppInstallScripts.openclaw.contains("\nURL='https://openclaw.ai/install.sh'\n"))
        XCTAssertTrue(AppInstallScripts.hermes.contains("\nURL='https://hermes-agent.nousresearch.com/install.sh'\n"))
        XCTAssertEqual(AppInstallScripts.openclaw.components(separatedBy: "https://").count, 2)
        XCTAssertEqual(AppInstallScripts.hermes.components(separatedBy: "https://").count, 2)
    }

    func testTheOpenclawEnvironmentAndVersionPinAreExactlyTheOnesMaasUses() {
        let environment = "CI=1 DEBIAN_FRONTEND=noninteractive OPENCLAW_NO_ONBOARD=1 OPENCLAW_NO_PROMPT=1 OPENCLAW_INSTALL_METHOD=npm OPENCLAW_VERSION=2026.9.4 \"OPENCLAW_INSTALL_URL=$URL\" bash \"$1\""
        XCTAssertTrue(AppInstallScripts.openclaw.contains(environment))
        XCTAssertTrue(AppInstallScripts.openclaw.contains("PREREQUISITES='curl ca-certificates'\n"))
    }

    func testTheHermesEnvironmentAndPrerequisitesAreExactlyTheOnesInTheBrief() {
        XCTAssertTrue(AppInstallScripts.hermes.contains("CI=1 DEBIAN_FRONTEND=noninteractive bash \"$1\""))
        XCTAssertTrue(AppInstallScripts.hermes.contains("PREREQUISITES='curl ca-certificates git libatomic1'\n"))
        XCTAssertFalse(AppInstallScripts.hermes.contains("OPENCLAW"))
    }

    func testTheStepsRunInOrderAndTheInstallerIsAFileNeverPiped() throws {
        let steps = ["BIN=$(find_app) && {", "apt-get update -y", "apt-get install -y $PREREQUISITES", "curl -fsSL --max-time \"$DOWNLOAD_SECONDS\" -o \"$FILE\" \"$URL\"",
                     "sha256sum \"$FILE\"", "run_installer \"$FILE\"", "BIN=$(find_app) || report false install_failed", "read_version \"$BIN\"\nreport true"]
        for kind in AppKind.allCases {
            let positions = try steps.map { try XCTUnwrap(kind.script.range(of: $0), $0).lowerBound }
            XCTAssertEqual(positions, positions.sorted())
            XCTAssertTrue(kind.script.contains("DOWNLOAD_SECONDS=120"))
            XCTAssertFalse(kind.script.contains("| bash") || kind.script.contains("|bash"), "never curl | bash")
            XCTAssertTrue(kind.script.contains("/root/.local/bin"))
            XCTAssertTrue(kind.script.contains("RESULT_MARKER='\(marker)'"))
        }
    }

    func testTheScriptsAreTheSameTextAsTheLinuxHelpersButForTheShape() {
        for kind in AppKind.allCases {
            XCTAssertTrue(kind.script.hasPrefix("APP=\(kind.rawValue)\n"))
            XCTAssertTrue(kind.script.hasSuffix("read_version \"$BIN\"\nreport true\n"))
        }
    }

    func testTheCallIsAFixedExecOfBashReadingStandardInputWithNoRequestData() {
        XCTAssertEqual(AppInstallCall.arguments(id: "w-abc"), ["exec", "-i", "ms-w-abc", "/bin/bash", "-s"])
        XCTAssertEqual(AppInstallCall.timeout, 1200)
    }

    // MARK: request

    func testTheTwoKnownAppsAreAccepted() throws {
        XCTAssertEqual(try AppInstallRequest(body: Data(#"{"app":"openclaw"}"#.utf8)).app, .openclaw)
        XCTAssertEqual(try AppInstallRequest(body: Data(#"{"app":"hermes"}"#.utf8)).app, .hermes)
    }

    func testEveryBadBodyIsRefused() {
        let bodies = [#"{"app":"nginx"}"#, #"{"app":"OpenClaw"}"#, #"{"app":""}"#, #"{"app":1}"#, #"{"app":null}"#, #"{"app":["hermes"]}"#,
                      "{}", #"{"app":"hermes","extra":true}"#, #"["hermes"]"#, "not json"]
        for body in bodies {
            XCTAssertThrowsError(try AppInstallRequest(body: Data(body.utf8)), body) { XCTAssertTrue($0 is InputError, body) }
        }
    }

    // MARK: result lines

    func testAFreshInstallReadsTheVersionAndTheHash() {
        let output = afterMarker(["app=openclaw", "installed=true", "version=OpenClaw 2026.9.4", "sha256=\(sha)"])
        let expected = AppInstalled(app: "openclaw", installed: true, version: "OpenClaw 2026.9.4", installerSha256: sha)
        XCTAssertEqual(AppInstallOutput.parse(output, app: .openclaw), .done(expected))
    }

    func testAnAppThatWasAlreadyThereHasNoHashAndInstalledFalse() {
        let output = afterMarker(["app=hermes", "installed=false", "version=0.4.1"])
        XCTAssertEqual(AppInstallOutput.parse(output, app: .hermes), .done(AppInstalled(app: "hermes", installed: false, version: "0.4.1", installerSha256: nil)))
    }

    func testAToolThatPrintsNoVersionGivesNull() {
        XCTAssertEqual(AppInstallOutput.parse(afterMarker(["app=hermes", "installed=true", "sha256=\(sha)"]), app: .hermes),
                       .done(AppInstalled(app: "hermes", installed: true, version: nil, installerSha256: sha)))
    }

    func testEachFailureCodeIsReadWithItsPlainWords() {
        let codes: [(String, AppScriptFailure)] = [("no_package_manager", .noPackageManager), ("prerequisites_failed", .prerequisitesFailed),
                                                   ("download_failed", .downloadFailed), ("install_failed", .installFailed)]
        for (code, failure) in codes {
            XCTAssertEqual(AppInstallOutput.parse(afterMarker(["app=hermes", "installed=false", "failure=\(code)"]), app: .hermes), .failed(failure))
            XCTAssertEqual(failure.rawValue, code)
            XCTAssertFalse(failure.message.isEmpty)
        }
        XCTAssertEqual(AppScriptFailure.downloadFailed.message, "The VM could not download the installer. Check that the VM has internet access.")
    }

    func testGarbageAndHalfAnswersAreNotGuessedAt() {
        XCTAssertNil(AppInstallOutput.parse(afterMarker(["app=openclaw", "installed=true"]), app: .hermes), "another app")
        let outputs = [afterMarker(["app=hermes"]), afterMarker(["app=hermes", "installed=maybe"]), afterMarker(["app=hermes", "installed=false", "failure=meteor"]),
                       "", "installed=true\napp=hermes\n", "\u{0}\u{1}garbage"]
        for output in outputs { XCTAssertNil(AppInstallOutput.parse(output, app: .hermes), output) }
    }

    func testOnlyTheLinesAfterTheLastMarkerCount() {
        let faked = "\(marker)\napp=hermes\ninstalled=true\n\(marker)\napp=hermes\ninstalled=false\nfailure=download_failed\n"
        XCTAssertEqual(AppInstallOutput.parse(faked, app: .hermes), .failed(.downloadFailed))
        let before = "installed=true\nfailure=install_failed\n\(marker)\napp=hermes\ninstalled=false\n"
        XCTAssertEqual(AppInstallOutput.parse(before, app: .hermes), .done(AppInstalled(app: "hermes", installed: false, version: nil, installerSha256: nil)))
    }

    func testABadVersionOrHashBecomesNullNotAnError() {
        let output = afterMarker(["app=hermes", "installed=true", "version=" + String(repeating: "9", count: 101), "sha256=nothex"])
        XCTAssertEqual(AppInstallOutput.parse(output, app: .hermes), .done(AppInstalled(app: "hermes", installed: true, version: nil, installerSha256: nil)))
    }

    func testTheAnswerEncodesLikeTheContractWithNullsKept() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppInstalled(app: "hermes", installed: false, version: nil, installerSha256: nil))) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["app", "installed", "version", "installer_sha256"])
        XCTAssertTrue(json["version"] is NSNull)
        XCTAssertTrue(json["installer_sha256"] is NSNull)
        XCTAssertEqual(json["installed"] as? Bool, false)
    }

    // MARK: log tail

    func testTheTailKeepsTheLastTwelveLinesBeforeTheMarker() {
        let body = (1...30).map { "line \($0)" }.joined(separator: "\n")
        let tail = AppInstallOutput.logTail("\(body)\n\(marker)\napp=hermes\ninstalled=false\n")
        XCTAssertEqual(tail.count, 12)
        XCTAssertEqual([tail.first, tail.last], ["line 19", "line 30"])
    }

    func testALongLineIsCutToTwoHundredCharacters() {
        XCTAssertEqual(AppInstallOutput.logTail(String(repeating: "é", count: 500) + "\n").first?.count, 200)
    }

    func testControlCharactersAreRemovedAndEmptyLinesDropped() {
        XCTAssertEqual(AppInstallOutput.logTail("\u{1b}[31mred\u{1b}[0m text\r\n\n\u{7}\ttab\u{0}bell\n   \n"), ["[31mred[0m text", "tabbell"])
    }

    func testAShortLogIsReturnedWholeAndNoOutputGivesAnEmptyTail() {
        XCTAssertEqual(AppInstallOutput.logTail("one\ntwo\n"), ["one", "two"])
        XCTAssertEqual(AppInstallOutput.logTail(""), [])
    }
}

/// The service and the simulated engine: what each failure turns into, and that nothing from a request reaches the recorded command line or the script.
final class AppInstallServiceTests: XCTestCase {
    private let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, ramTotalMb: 32768, diskTotalGb: 500, gpu: [])

    private func machine(running: Bool = true) async throws -> (AgentService, SimulatedEngine, String) {
        let engine = SimulatedEngine()
        let request = try CreateWorkloadRequest(body: JSONSerialization.data(withJSONObject: ["command_id": "c-1", "name": "demo", "kind": "vm", "cpu": 1, "ram_mb": 1024, "disk_gb": 5]))
        let made = try await engine.create(id: "w-1", request: request)
        if !running { try await engine.setRunning(id: made.id, running: false) }
        let service = AgentService(engine: engine, budget: SpaceBudget(ramTotalMb: 32768, diskTotalGb: 1000), specs: specs, agentVersion: "0.9.9")
        return (service, engine, made.id)
    }

    func testAFreshInstallWorksAndASecondOneChangesNothing() async throws {
        let (service, engine, id) = try await machine()
        let first = try await service.installApp(id: id, app: .openclaw)
        XCTAssertEqual(first, AppInstalled(app: "openclaw", installed: true, version: SimulatedAppInstall.version, installerSha256: SimulatedAppInstall.sha256))
        let second = try await service.installApp(id: id, app: .openclaw)
        XCTAssertEqual(second, AppInstalled(app: "openclaw", installed: false, version: SimulatedAppInstall.version, installerSha256: nil))
        let hasOpenclaw = await engine.hasApp(.openclaw, id: id), hasHermes = await engine.hasApp(.hermes, id: id)
        XCTAssertTrue(hasOpenclaw)
        XCTAssertFalse(hasHermes, "the other app is separate")
    }

    func testTheRecordedCallIsTheConstantScriptWithNoRequestDataInTheArguments() async throws {
        let (service, engine, id) = try await machine()
        _ = try await service.installApp(id: id, app: .hermes)
        _ = try await service.installApp(id: id, app: .openclaw)
        let runs = await engine.appInstallRuns
        XCTAssertEqual(runs.map(\.arguments), [AppInstallCall.arguments(id: id), AppInstallCall.arguments(id: id)])
        XCTAssertEqual(runs.map(\.input), [Data(AppInstallScripts.hermes.utf8), Data(AppInstallScripts.openclaw.utf8)])
        XCTAssertFalse(runs[0].arguments.joined(separator: " ").contains("hermes"), "the choice is only which script goes on standard input")
    }

    func testAnUnknownVmIsNotFoundAndAStoppedVmIsNotRunning() async throws {
        let (service, _, _) = try await machine()
        do { _ = try await service.installApp(id: "w-nope", app: .hermes); XCTFail("unknown") } catch { XCTAssertEqual(error as? EngineError, .notFound) }
        let (stoppedService, engine, id) = try await machine(running: false)
        do { _ = try await stoppedService.installApp(id: id, app: .hermes); XCTFail("stopped") } catch { XCTAssertEqual(error as? EngineError, .notRunning) }
        let runs = await engine.appInstallRuns
        XCTAssertTrue(runs.isEmpty, "nothing ran in a stopped VM")
    }

    func testEveryFailureCodeIsAnAppInstallFailureWithPlainWordsAndTheInstallersLastLines() async throws {
        let failures: [AppScriptFailure] = [.noPackageManager, .prerequisitesFailed, .downloadFailed, .installFailed]
        for failure in failures {
            let (service, engine, id) = try await machine()
            await engine.setAppInstall(.fails(failure))
            do { _ = try await service.installApp(id: id, app: .openclaw); XCTFail("should fail") } catch {
                XCTAssertEqual(error as? AppInstallFailure, AppInstallFailure(message: failure.message, logTail: ["simulated installer output"]))
            }
            let installed = await engine.hasApp(.openclaw, id: id)
            XCTAssertFalse(installed)
        }
    }

    func testAnUnreadableReportAndABrokenRunAreFailuresToo() async throws {
        let (service, engine, id) = try await machine()
        await engine.setAppInstall(.garbage)
        do { _ = try await service.installApp(id: id, app: .hermes); XCTFail("garbage") } catch {
            XCTAssertEqual(error as? AppInstallFailure, AppInstallFailure(message: AppInstallFailure.unreadableMessage, logTail: ["something else entirely"]))
        }
        await engine.setAppInstall(.breaks)
        do { _ = try await service.installApp(id: id, app: .hermes); XCTFail("broken") } catch {
            let failure = error as? AppInstallFailure
            XCTAssertEqual(failure, AppInstallFailure(message: AppInstallFailure.unfinishedMessage, logTail: []))
            XCTAssertFalse(failure?.message.contains("engine-detail-xyz") ?? true, "the engine's own text stays out of the answer")
        }
        XCTAssertEqual(AppInstallFailure.errorCode, "app_install_failed")
    }

    func testASlowInstallStillWorks() async throws {
        let (service, engine, id) = try await machine()
        await engine.setAppInstall(.delay(0.2))
        let done = try await service.installApp(id: id, app: .hermes)
        XCTAssertTrue(done.installed)
    }

    func testTheUnavailableEngineHasNoVms() async {
        let engine = UnavailableEngine(name: "apple-container", problem: HostProblem(code: "x", message: "m", fix: "f"))
        do { _ = try await engine.installApp(id: "w-1", app: .hermes); XCTFail("unavailable") } catch { XCTAssertEqual(error as? EngineError, .notFound) }
    }
}
