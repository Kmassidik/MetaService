import XCTest
@testable import RootCore

final class HelperUpdateTests: XCTestCase {
    private let old = String(repeating: "a", count: 64)
    private let newest = String(repeating: "b", count: 64)
    private lazy var builds = ["darwin-arm64": newest, "linux-x86_64": old]

    func testTheSystemNameIsTheOneTheBuildsGoBy() {
        XCTAssertEqual(HelperUpdateRules.system(os: "macos", arch: "arm64"), "darwin-arm64")
        XCTAssertEqual(HelperUpdateRules.system(os: "linux", arch: "x86_64"), "linux-x86_64")
        XCTAssertEqual(HelperUpdateRules.system(os: "linux", arch: "aarch64"), "linux-arm64")
        XCTAssertEqual(HelperUpdateRules.system(os: "linux", arch: "arm64"), "linux-arm64")
        XCTAssertNil(HelperUpdateRules.system(os: nil, arch: nil))
    }

    func testADifferentBuildCanBeUpdated() {
        let update = HelperUpdateRules.decide(os: "macos", arch: "arm64", reported: old, builds: builds)
        XCTAssertEqual(update, HelperUpdate(available: true, currentBuild: old, newestBuild: newest, reason: nil))
    }

    func testTheSameBuildIsUpToDate() {
        let update = HelperUpdateRules.decide(os: "macos", arch: "arm64", reported: newest, builds: builds)
        XCTAssertFalse(update.available)
        XCTAssertEqual(update.currentBuild, newest)
        XCTAssertNil(update.reason)
    }

    func testAnOlderHelperThatDoesNotSayItsBuildCountsAsUpdatable() {
        let update = HelperUpdateRules.decide(os: "macos", arch: "arm64", reported: nil, builds: builds)
        XCTAssertEqual(update, HelperUpdate(available: true, currentBuild: nil, newestBuild: newest, reason: nil))
    }

    func testASystemWithoutABuildHasNothingToOfferAndSaysWhy() {
        let update = HelperUpdateRules.decide(os: "linux", arch: "aarch64", reported: old, builds: builds)
        XCTAssertFalse(update.available)
        XCTAssertNil(update.newestBuild)
        XCTAssertEqual(update.currentBuild, old)
        XCTAssertEqual(update.reason, HelperUpdateRules.noBuildReason)
    }

    func testAMachineThatNeverReportedHasNoSystemYet() {
        let update = HelperUpdateRules.decide(os: nil, arch: nil, reported: nil, builds: builds)
        XCTAssertFalse(update.available)
        XCTAssertEqual(update.reason, HelperUpdateRules.notReportedReason)
    }

    func testTheUpdateIsSentWithAllFourKeysAndNullsStayNulls() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HelperUpdate(available: true, currentBuild: nil, newestBuild: newest, reason: nil))) as! [String: Any]
        XCTAssertEqual(Set(json.keys), ["available", "currentBuild", "newestBuild", "reason"])
        XCTAssertTrue(json["currentBuild"] is NSNull)
        XCTAssertTrue(json["reason"] is NSNull)
    }

    func testABuildIsSixtyFourLowercaseHexDigits() {
        XCTAssertTrue(AgentBuild.isValid(old))
        for bad in ["", "abc", String(repeating: "A", count: 64), String(repeating: "g", count: 64), old + "0", "../" + String(repeating: "a", count: 61)] { XCTAssertFalse(AgentBuild.isValid(bad), bad) }
        XCTAssertEqual(AgentBuild.short(old), "aaaaaaaa")
    }
}
