import XCTest
import RootCore
@testable import RootStore

final class AutoPinTests: XCTestCase {
    private var database: Database!
    private var directory: String!
    private var store: BundleStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        directory = NSTemporaryDirectory() + "ms-bundles-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        store = BundleStore(database, directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: directory)
    }

    private func build(_ version: String) throws {
        FileManager.default.createFile(atPath: directory + "/" + BundleFile.fileName(version: version, platform: "noarch"), contents: Data("bundle \(version)".utf8))
    }

    func testTheOnlyBuiltVersionIsPinnedWhenNothingIsPinned() throws {
        try build("0.4.0")
        XCTAssertEqual(try store.pinTheOnlyBuiltVersion(actor: "root", now: now), "0.4.0")
        XCTAssertEqual(try store.pinned(), "0.4.0")
    }

    func testNothingBuiltMeansNothingIsPinned() throws {
        XCTAssertNil(try store.pinTheOnlyBuiltVersion(actor: "root", now: now))
        XCTAssertNil(try store.pinned())
        XCTAssertTrue(try store.overview(now: now).bundles.isEmpty, "this is what 'no chat is built' means")
    }

    func testTwoBuiltVersionsAreLeftForThePersonToChoose() throws {
        try build("0.3.0")
        try build("0.4.0")
        XCTAssertNil(try store.pinTheOnlyBuiltVersion(actor: "root", now: now))
        XCTAssertNil(try store.pinned())
    }

    func testAPinThePersonMadeIsNeverChanged() throws {
        try build("0.4.0")
        try store.pin(version: "0.4.0", actor: "kurnia", now: now)
        XCTAssertNil(try store.pinTheOnlyBuiltVersion(actor: "root", now: now))
        XCTAssertEqual(try store.pinned(), "0.4.0")
    }

    func testRunningItAgainPinsNothingNew() throws {
        try build("0.4.0")
        _ = try store.pinTheOnlyBuiltVersion(actor: "root", now: now)
        XCTAssertNil(try store.pinTheOnlyBuiltVersion(actor: "root", now: now))
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM bundle_pins").first?.int("n"), 1)
    }
}
