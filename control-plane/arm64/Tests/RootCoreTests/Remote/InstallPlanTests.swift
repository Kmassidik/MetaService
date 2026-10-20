import XCTest
@testable import RootCore

final class InstallPlanTests: XCTestCase {
    private func options(_ change: (inout RemoteInstallOptions) -> Void = { _ in }) -> RemoteInstallOptions {
        var value = RemoteInstallOptions.defaults(name: "office-mini", home: "/Users/kurnia", engine: "apple", rootURL: "http://192.168.100.40:9102")
        change(&value)
        return value
    }
    private func plan(_ change: (inout RemoteInstallOptions) -> Void = { _ in }) throws -> InstallPlan { try InstallPlan.make(options(change), agentSize: 12 * 1_048_576) }

    func testTheStepsComeInTheOrderTheyMustRun() throws {
        XCTAssertEqual(try plan().steps.map(\.id), ["folder", "agent", "enroll", "start", "key", "manifest"])
        XCTAssertEqual(try plan { $0.installKey = false }.steps.map(\.id), ["folder", "agent", "enroll", "start", "manifest"])
    }

    func testEveryStepSaysInPlainWordsWhatItChanges() throws {
        for step in try plan().steps {
            XCTAssertFalse(step.changes.isEmpty, step.id)
            XCTAssertTrue(step.changes.allSatisfy { !$0.isEmpty }, step.id)
            XCTAssertFalse(step.label.isEmpty)
        }
        let all = try plan().steps.flatMap(\.changes).joined(separator: " ")
        XCTAssertTrue(all.contains("/Users/kurnia/metaservice-box"))
        XCTAssertTrue(all.contains("12 MB"))
        XCTAssertTrue(all.contains("127.0.0.1:9101"))
        XCTAssertTrue(all.contains("ONE line") && all.contains("authorized_keys") && all.contains("metaservice-office-mini"))
    }

    func testTheFolderLevelNeverNeedsAdminRights() throws {
        let operations = try plan().steps.flatMap(\.operations)
        XCTAssertFalse(operations.contains { if case .runAsAdmin = $0 { return true } else { return false } })
    }

    func testEverythingItCreatesIsInsideTheBox() throws {
        let value = try plan()
        XCTAssertTrue(value.createdPaths.allSatisfy { $0 == value.options.box || $0.hasPrefix(value.options.box + "/") }, "\(value.createdPaths)")
        XCTAssertEqual(value.createdPaths.first, "/Users/kurnia/metaservice-box")
        XCTAssertTrue(value.createdPaths.contains("/Users/kurnia/metaservice-box/bin/metaservice-agent"))
    }

    func testTheOnlyChangeOutsideTheBoxIsTheOneKeyLine() throws {
        let outside = try plan().steps.flatMap(\.operations).filter { operation in
            switch operation {
            case .makeFolder(let path, _), .putFile(let path, _, _): return !path.hasPrefix("/Users/kurnia/metaservice-box")
            case .addKeyLine, .runAsAdmin: return true
            case .run: return false
            }
        }
        XCTAssertEqual(outside, [.addKeyLine(file: "/Users/kurnia/.ssh/authorized_keys")])
        XCTAssertTrue(try plan { $0.installKey = false }.steps.flatMap(\.operations).allSatisfy { if case .addKeyLine = $0 { return false } else { return true } })
    }

    func testTheManifestIsTheLastStepSoItOnlyExistsWhenEverythingElseWorked() throws {
        XCTAssertEqual(try plan().steps.last?.id, "manifest")
    }

    func testTheEnrollmentTokenNeverAppearsInAPlanItself() throws {
        let value = try plan()
        XCTAssertTrue(value.steps.flatMap(\.operations).contains(.putFile(path: "/Users/kurnia/metaservice-box/state/enroll.token", mode: "600", source: .enrollToken)))
        XCTAssertFalse("\(value)".lowercased().contains("secret"))
    }

    func testABadOptionStopsTheWholePlan() {
        XCTAssertThrowsError(try plan { $0.box = "/a b" })
        XCTAssertThrowsError(try plan { $0.name = "Bad" })
    }

    func testScreenControlIsOffUnlessAskedForAndSaysSoInPlainWords() throws {
        let off = try plan()
        XCTAssertFalse(PlanScripts.runArguments(off.options).contains("--screen"))
        XCTAssertFalse(off.steps.flatMap(\.changes).joined().contains("screen"))
        let on = try plan { $0.allowScreen = true }
        XCTAssertEqual(PlanScripts.runArguments(on.options).drop { $0 != "--screen" }.prefix(2).last, "mac")
        XCTAssertTrue(on.steps.first { $0.id == "start" }!.changes.joined().contains("screen"))
        XCTAssertTrue(on.steps.first { $0.id == "start" }!.changes.joined().contains("Screen Recording and Accessibility"))
        let simulated = try plan { $0.allowScreen = true; $0.engine = "simulated" }
        XCTAssertEqual(PlanScripts.runArguments(simulated.options).drop { $0 != "--screen" }.prefix(2).last, "simulated")
    }
}
