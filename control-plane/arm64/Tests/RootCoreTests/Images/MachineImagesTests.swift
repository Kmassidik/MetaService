import XCTest
@testable import RootCore

final class MachineImagesTests: XCTestCase {
    private func row(_ id: String, ready: Bool = true, builtAt: Any = NSNull()) -> [String: Any] { ["id": id, "ready": ready, "built_at": builtAt] }

    func testAHelperAnswerIsReadStrictly() {
        XCTAssertEqual(HelperImage.parse(["images": [row("blank")]]), [HelperImage(id: "blank", ready: true)])
        XCTAssertEqual(HelperImage.parse(["images": [row("openclaw", builtAt: "2026-10-22T10:00:00Z")]])?.first?.id, "openclaw")
        XCTAssertEqual(HelperImage.parse(["images": [Any]()]), [])
    }

    func testAnythingElseIsRefused() {
        let bad: [[String: Any]?] = [nil, [:], ["images": "x"], ["images": [row("blank")], "extra": 1], ["images": [["id": "blank", "ready": true]]],
                                     ["images": [["id": "blank", "ready": "yes", "built_at": NSNull()]]], ["images": [row("Bad Id")]], ["images": [row("blank"), row("blank")]],
                                     ["images": [["id": "blank", "ready": true, "built_at": 5]]], ["images": [["id": "blank", "ready": true, "built_at": NSNull(), "path": "/bin"]]],
                                     ["images": Array(repeating: row("blank"), count: 17)]]
        for item in bad { XCTAssertNil(HelperImage.parse(item), "\(String(describing: item))") }
    }

    func testBlankIsReadyEverywhereEvenWhenTheHelperIsOldOrSilent() {
        for helper in [HelperImagesAnswer.oldHelper, .unreachable, .answered([])] {
            let blank = MachineImagesReply.merge(helper).images[0]
            XCTAssertEqual([blank.id, "\(blank.ready)", "\(blank.available)"], ["blank", "true", "true"], "\(helper)")
            XCTAssertNil(blank.reason)
        }
    }

    func testAnAppIsAvailableExactlyWhenTheHelperSaysItIsReady() {
        let claims = HelperImagesAnswer.answered([HelperImage(id: "openclaw", ready: true), HelperImage(id: "hermes", ready: true)])
        let images = MachineImagesReply.merge(claims).images
        XCTAssertEqual(images.map(\.available), [true, true, true])
        XCTAssertEqual(images.map(\.state), [.ready, .ready, .ready])
        XCTAssertEqual(images.map(\.reason), [nil, nil, nil])
    }

    func testAnAppTheHelperDoesNotReportReadyKeepsAReasonThatSendsPeopleToUpdateTheHelper() {
        let notReady = HelperImagesAnswer.answered([HelperImage(id: "openclaw", ready: false)])
        for helper in [notReady, .oldHelper, .answered([])] {
            let images = MachineImagesReply.merge(helper).images
            XCTAssertEqual(images.map(\.available), [true, false, false], "\(helper)")
            XCTAssertEqual(images[1].reason, "Update the helper on this machine first")
            XCTAssertEqual(images[2].reason, "Update the helper on this machine first")
            XCTAssertEqual(images[1].state, .planned)
        }
    }

    func testAnUnreachableMachineKeepsTheCatalogsOwnReasonForApps() {
        let images = MachineImagesReply.merge(.unreachable).images
        XCTAssertEqual(images.map(\.available), [true, false, false])
        XCTAssertEqual(images[1].reason, "Coming soon: needs the image to be prepared on the machine")
        XCTAssertEqual(images[2].reason, "Waiting for a pinned release and checksum")
    }

    func testACaptionIsAllowedAndReadStrictly() {
        let captioned: [String: Any] = ["id": "openclaw", "ready": true, "built_at": NSNull(), "caption": "Installs after the VM starts, about 2 minutes"]
        XCTAssertEqual(HelperImage.parse(["images": [captioned]]), [HelperImage(id: "openclaw", ready: true)])
        var tooLong = captioned
        tooLong["caption"] = String(repeating: "x", count: 201)
        XCTAssertNil(HelperImage.parse(["images": [tooLong]]))
        var notText = captioned
        notText["caption"] = 5
        XCTAssertNil(HelperImage.parse(["images": [notText]]))
    }

    func testAnAppIsNeverSentToAHelperAsAnImage() {
        XCTAssertNil(ImageCatalog.helperBundle(for: "openclaw"))
        XCTAssertNil(ImageCatalog.helperBundle(for: "hermes"))
    }

    func testTheReplyNamesWhoAnswered() {
        XCTAssertEqual(MachineImagesReply.merge(.oldHelper).helper, "old_helper")
        XCTAssertEqual(MachineImagesReply.merge(.unreachable).helper, "unreachable")
        XCTAssertEqual(MachineImagesReply.merge(.answered([])).helper, "answered")
    }

    func testAReadyCatalogEntryNeedsTheMachineToHaveItToo() {
        let entry = ImageEntry(id: "devbox", title: "Devbox", description: "x", state: .ready, reason: nil, pinnedVersion: "1.0.0", sha256: String(repeating: "a", count: 64))
        let missing = MachineImagesReply.merge(.answered([]), catalog: [entry]).images[0]
        XCTAssertEqual([missing.ready, missing.available], [false, false])
        XCTAssertEqual(missing.reason, "This machine has to prepare the image first")
        let there = MachineImagesReply.merge(.answered([HelperImage(id: "devbox", ready: true)]), catalog: [entry]).images[0]
        XCTAssertEqual([there.ready, there.available], [true, true])
        XCTAssertNil(there.reason)
    }

    func testWhatTheHelperSaysAboutNamesNotInTheCatalogNeverReachesThePanel() throws {
        let reply = MachineImagesReply.merge(.answered([HelperImage(id: "evil-image", ready: true)]))
        XCTAssertEqual(reply.images.map(\.id), ["blank", "openclaw", "hermes"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reply)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["helper", "images"])
        let first = try XCTUnwrap((json["images"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(first.keys), ["id", "title", "description", "state", "ready", "available", "reason"])
    }
}
