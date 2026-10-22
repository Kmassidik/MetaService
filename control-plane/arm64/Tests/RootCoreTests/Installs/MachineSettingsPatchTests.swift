import MSCore
import XCTest
@testable import RootCore

final class MachineSettingsPatchTests: XCTestCase {
    static let hostile = ["'; DROP TABLE machines;--", "<script>alert(1)</script>", "$(reboot)", "`id`", "../../etc/passwd", "line\nbreak", "nul\u{0}byte", String(repeating: "x", count: 1000),
                          "{@html x}", "--privileged", "a b", "; reboot", "%s%n", "Ünïcode", "", " "]

    private func patch(_ fields: [String: Any]) throws -> MachineSettingsPatch {
        try MachineSettingsPatch(body: JSONSerialization.data(withJSONObject: fields))
    }

    private func applied(_ fields: [String: Any], to settings: MachineSettings = MachineSettings()) throws -> MachineSettings {
        try patch(fields).applying(to: settings)
    }

    func testEveryAllowedFieldChangesOnlyItself() throws {
        let start = MachineSettings(profile: "gpu-box", notes: "keep", publicChat: true)
        let next = try applied(["labels": ["office", "gpu"], "notes": "under the desk", "allow_gpu": false, "ram_reserve_mb": 4096, "disk_reserve_gb": 30, "ram_allowance_mb": 65536,
                                "disk_allowance_gb": 900, "vm_max_running": 6, "vm_cpu": 4, "vm_ram_mb": 8192, "vm_disk_gb": 60, "vm_image": "images:ubuntu/24.04",
                                "subdomain": "dgx1", "ai_model": "anthropic/claude-sonnet-5"], to: start)
        XCTAssertEqual([next.labels.joined(separator: ","), next.notes, next.vmImage, next.subdomain, next.aiModel], ["office,gpu", "under the desk", "images:ubuntu/24.04", "dgx1", "anthropic/claude-sonnet-5"])
        XCTAssertEqual([next.ramReserveMb, next.diskReserveGb, next.ramAllowanceMb, next.diskAllowanceGb, next.vmMaxRunning, next.vmCpu, next.vmRamMb, next.vmDiskGb], [4096, 30, 65536, 900, 6, 4, 8192, 60])
        XCTAssertFalse(next.allowGpu)
        XCTAssertEqual(next.profile, "gpu-box", "the profile is not editable here and stays")
        XCTAssertTrue(next.publicChat, "public chat is not editable here and stays")
    }

    func testAFieldNotMentionedStaysAndNullClearsWhatCanBeEmpty() throws {
        let start = MachineSettings(ramReserveMb: 4096, vmCpu: 4, vmImage: "ubuntu:24.04", subdomain: "mini", aiModel: "m/x")
        let next = try applied(["vm_cpu": 8, "vm_image": NSNull(), "ai_model": NSNull(), "ram_reserve_mb": NSNull()], to: start)
        XCTAssertEqual(next.vmCpu, 8)
        XCTAssertNil(next.vmImage)
        XCTAssertNil(next.aiModel)
        XCTAssertNil(next.ramReserveMb)
        XCTAssertEqual(next.subdomain, "mini")
    }

    func testTheNameIsReadAndReportedAsChanged() throws {
        let one = try patch(["name": "mac-studio", "notes": "x"])
        XCTAssertEqual(one.name, "mac-studio")
        XCTAssertEqual(one.changed, ["name", "notes"])
        XCTAssertNil(try patch(["notes": "x"]).name)
    }

    func testAFieldThatIsNotInTheAllowListIsRefused() {
        let refused: [String] = ["profile", "public_chat", "id", "bundle_version", "ip", "box", "agent_port", "agent_version", "token", "command", "path", "settings", "__proto__"]
        for key in refused { XCTAssertThrowsError(try patch([key: "x"]), key) }
    }

    func testAnEmptyChangeAndBrokenBodiesAreRefused() {
        XCTAssertThrowsError(try patch([:]))
        for raw in ["", "{", "null", "[]", "\"text\"", "1"] { XCTAssertThrowsError(try MachineSettingsPatch(body: Data(raw.utf8)), raw) }
    }

    func testFieldsThatAlwaysHoldSomethingCannotBeCleared() {
        for key in ["name", "labels", "notes", "allow_gpu"] { XCTAssertThrowsError(try patch([key: NSNull()]), key) }
    }

    func testHostileTextIsRefusedOrKeptAsPlainTextInEveryTextField() throws {
        let patterned = ["name", "subdomain", "vm_image", "ai_model"]
        for key in patterned {
            for text in Self.hostile { XCTAssertThrowsError(try patch([key: text]), "\(key): \(text.prefix(20))") }
        }
        for text in Self.hostile { XCTAssertThrowsError(try patch(["labels": [text]]), "label: \(text.prefix(20))") }
        for text in Self.hostile where text.count <= MachineSettings.maxNotes {
            XCTAssertEqual(try applied(["notes": text]).notes, text, "notes are free text, stored as given")
        }
        XCTAssertThrowsError(try patch(["notes": String(repeating: "x", count: MachineSettings.maxNotes + 1)]))
    }

    func testHostileValuesOfTheWrongTypeAreRefusedInEveryField() {
        let wrongForNumbers: [Any] = ["12", "1; reboot", true, 1.5, [1], ["a": 1], -1, 99_999_999_999_999_999]
        for key in ["ram_reserve_mb", "disk_reserve_gb", "ram_allowance_mb", "disk_allowance_gb", "vm_max_running", "vm_cpu", "vm_ram_mb", "vm_disk_gb"] {
            for value in wrongForNumbers { XCTAssertThrowsError(try patch([key: value]), "\(key) \(value)") }
        }
        for value in [1, "true", "no", NSNull(), [true]] as [Any] { XCTAssertThrowsError(try patch(["allow_gpu": value]), "allow_gpu \(value)") }
        for value in ["office", 5, ["a": 1], [1], [["x"]]] as [Any] { XCTAssertThrowsError(try patch(["labels": value]), "labels \(value)") }
        for value in [5, true, ["a"], ["a": 1]] as [Any] { XCTAssertThrowsError(try patch(["notes": value]), "notes \(value)") }
    }

    func testEveryNumberIsHeldToTheSameRangeTheAddFormUses() {
        let outOfRange: [(String, Int)] = [("ram_reserve_mb", -1), ("disk_reserve_gb", -1), ("ram_allowance_mb", 100), ("disk_allowance_gb", 0), ("vm_max_running", 0), ("vm_max_running", 1001),
                                           ("vm_cpu", 0), ("vm_cpu", 65), ("vm_ram_mb", 511), ("vm_disk_gb", 0), ("vm_disk_gb", 100_001)]
        for (key, value) in outOfRange { XCTAssertThrowsError(try patch([key: value]), "\(key) \(value)") }
    }

    func testTheReserveIsComparedWithTheAllowanceThatWasAlreadyThere() throws {
        let start = MachineSettings(diskReserveGb: 100, ramAllowanceMb: 8192)
        XCTAssertThrowsError(try applied(["ram_reserve_mb": 8192], to: start))
        XCTAssertThrowsError(try applied(["disk_allowance_gb": 100], to: start))
        XCTAssertEqual(try applied(["ram_reserve_mb": 4096], to: start).ramReserveMb, 4096)
    }

    func testTooManyOrRepeatedLabelsAreRefused() {
        XCTAssertThrowsError(try patch(["labels": (0..<9).map { "l\($0)" }]))
        XCTAssertThrowsError(try patch(["labels": ["a", "a"]]))
        XCTAssertNoThrow(try patch(["labels": []]), "no labels is allowed: it clears them")
    }

    func testTheSshAddressIsCheckedSavedAndCleared() throws {
        XCTAssertEqual(try applied(["ssh_jump": "you@203.0.113.7"]).sshJump, "you@203.0.113.7")
        XCTAssertEqual(try applied(["ssh_jump": "you@studio.example.com:2222"]).sshJump, "you@studio.example.com:2222")
        XCTAssertNil(try applied(["ssh_jump": NSNull()], to: MachineSettings(sshJump: "you@h")).sshJump)
        XCTAssertEqual(try applied(["notes": "x"], to: MachineSettings(sshJump: "you@h")).sshJump, "you@h", "not mentioned stays")
        for text in Self.hostile + ["host", "you@", "you@h:99999", "you@h; id", String(repeating: "a", count: 130) + "@h"] {
            XCTAssertThrowsError(try patch(["ssh_jump": text]), "ssh_jump: \(text.prefix(20))")
        }
    }
}
