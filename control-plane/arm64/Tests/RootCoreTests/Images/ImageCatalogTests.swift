import XCTest
@testable import RootCore

final class ImageCatalogTests: XCTestCase {
    func testTheCatalogListsBlankThenOpenClawThenHermes() {
        XCTAssertEqual(ImageCatalog.entries.map(\.id), ["blank", "openclaw", "hermes"])
        XCTAssertEqual(ImageCatalog.entries.map(\.state), [.ready, .planned, .planned])
    }

    func testOnlyBlankIsSelectableToday() {
        XCTAssertEqual(ImageCatalog.entries.filter(\.isSelectable).map(\.id), ["blank"])
    }

    func testPlannedEntriesSayWhyInPlainWords() {
        XCTAssertEqual(ImageCatalog.entry(id: "openclaw")?.reason, "Coming soon: needs the image to be prepared on the machine")
        XCTAssertEqual(ImageCatalog.entry(id: "hermes")?.reason, "Waiting for a pinned release and checksum")
        XCTAssertNil(ImageCatalog.entry(id: "blank")?.reason)
    }

    func testPlannedEntriesPinNothingYet() {
        for entry in ImageCatalog.entries where entry.state == .planned {
            XCTAssertNil(entry.pinnedVersion, entry.id)
            XCTAssertNil(entry.sha256, entry.id)
        }
    }

    func testTheBrowserOnlySeesIdTitleDescriptionStateAndReason() throws {
        let data = try JSONEncoder().encode(ImageCatalog.entries)
        let list = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        for item in list { XCTAssertEqual(Set(item.keys), ["id", "title", "description", "state", "reason"]) }
        XCTAssertTrue(list[0]["reason"] is NSNull, "a ready entry sends reason null, not a missing key")
        XCTAssertEqual(list[1]["state"] as? String, "planned")
    }

    func testUnknownNamesAreNotInTheCatalog() {
        for name in ["", "Blank", "ubuntu:24.04", "../etc", "openclaw ", "blank;ls", "images:ubuntu/24.04"] { XCTAssertNil(ImageCatalog.entry(id: name), name) }
    }

    func testBlankIsNeverSentToAHelperSoOldHelpersKeepWorking() {
        XCTAssertNil(ImageCatalog.helperBundle(for: "blank"))
    }

    func testAPlannedEntryIsNeverSentToAHelper() {
        XCTAssertNil(ImageCatalog.helperBundle(for: "openclaw"))
        XCTAssertNil(ImageCatalog.helperBundle(for: "hermes"))
    }

    func testAReadyEntryThatIsNotBlankIsSentByItsId() {
        let ready = ImageEntry(id: "openclaw", title: "OpenClaw", description: "x", state: .ready, reason: nil, pinnedVersion: "1.0.0", sha256: String(repeating: "a", count: 64))
        XCTAssertEqual(ImageCatalog.helperBundle(for: "openclaw", in: [ready]), "openclaw")
    }

    func testChoosingFallsBackToBlankAndRefusesTheRest() throws {
        XCTAssertEqual(try ImageCatalog.choose(nil).id, "blank")
        XCTAssertEqual(try ImageCatalog.choose("blank").id, "blank")
        XCTAssertThrowsError(try ImageCatalog.choose("nope")) { XCTAssertEqual($0 as? ImageChoiceError, .unknown) }
        XCTAssertThrowsError(try ImageCatalog.choose("hermes")) {
            XCTAssertEqual($0 as? ImageChoiceError, .notAvailable(reason: "Waiting for a pinned release and checksum"))
        }
    }
}
