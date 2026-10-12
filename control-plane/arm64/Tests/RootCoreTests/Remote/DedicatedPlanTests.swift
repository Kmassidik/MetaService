import XCTest
@testable import RootCore

final class DedicatedPlanTests: XCTestCase {
    private func options(ram: Int? = nil) -> RemoteInstallOptions {
        var value = RemoteInstallOptions.defaults(name: "office-linux", home: "/home/kurnia", engine: "incus", rootURL: "http://192.168.100.40:9102")
        value.settings.ramAllowanceMb = ram
        return value
    }

    private func shellAccepts(_ text: String) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", "-c", text]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    func testStepsAreInOrderAndAllAdminWorkIsMarked() {
        let steps = DedicatedPlan.make(options(), agentSize: 9_000_000)
        XCTAssertEqual(steps.map(\.id), ["user", "folder", "agent", "enroll", "unit", "start"])
        for step in steps { XCTAssertFalse(step.changes.isEmpty, "\(step.id) says what it changes") }
        XCTAssertTrue(steps[0].operations.allSatisfy { if case .runAsAdmin = $0 { return true } else { return false } })
    }

    func testUnitIsHardenedAndCapsMemory() {
        let text = DedicatedPlan.unitText(options(ram: 8192))
        for line in ["User=metaservice", "NoNewPrivileges=yes", "ProtectSystem=strict", "ReadWritePaths=/opt/metaservice", "PrivateTmp=yes", "MemoryMax=8192M"] {
            XCTAssertTrue(text.contains(line), line)
        }
        XCTAssertTrue(text.contains("'--bind' '127.0.0.1'"), "listens on loopback only")
        XCTAssertFalse(DedicatedPlan.unitText(options()).contains("MemoryMax"), "no cap when no allowance was set")
    }

    func testEveryCommandAndScriptIsValidShell() throws {
        let commands = DedicatedPlan.make(options(), agentSize: nil).flatMap(\.operations).compactMap { operation -> String? in
            if case .runAsAdmin(let command) = operation { return command } else { return nil }
        }
        for command in commands + [DedicatedPlan.beforeScript, DedicatedPlan.removeScript] { XCTAssertTrue(try shellAccepts(command), command) }
    }

    func testNothingExistingIsModified() {
        let text = (DedicatedPlan.make(options(), agentSize: nil).flatMap(\.operations).map { "\($0)" } + [DedicatedPlan.beforeScript]).joined()
        for forbidden in ["apt ", "yum ", "dnf ", "usermod", "sed -i", "visudo", "/etc/ssh", "sudoers"] { XCTAssertFalse(text.contains(forbidden), forbidden) }
    }

    func testRemovalRefusesWithoutARecord() {
        XCTAssertTrue(DedicatedPlan.removeScript.contains("not a MetaService box"))
        XCTAssertTrue(DedicatedPlan.beforeScript.contains("exit 20"))
    }
}
