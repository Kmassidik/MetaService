import XCTest
@testable import RootCore

final class InstallRequestTests: XCTestCase {
    private func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    func testAGoodRequestIsRead() throws {
        let request = try InstallRequest(body: data(["target": "this", "name": "macbook", "chat": true, "ram_reserve_mb": 4096, "disk_reserve_gb": 30]))
        XCTAssertEqual(request, try InstallRequest(body: data(["target": "this", "name": "macbook", "chat": true, "ram_reserve_mb": 4096, "disk_reserve_gb": 30])))
        XCTAssertEqual([request.name, String(request.chat), String(request.ramReserveMb!), String(request.diskReserveGb!)], ["macbook", "true", "4096", "30"])
        let bare = try InstallRequest(body: data(["target": "this", "name": "mini", "chat": false]))
        XCTAssertNil(bare.ramReserveMb)
        XCTAssertNil(bare.diskReserveGb)
    }

    func testEveryBrokenRequestIsRefused() {
        let good: [String: Any] = ["target": "this", "name": "mini", "chat": true]
        let broken: [(String, [String: Any])] = [
            ("another computer is not built yet", good.merging(["target": "10.0.0.5"]) { $1 }), ("no target", good.filter { $0.key != "target" }),
            ("bad name", good.merging(["name": "Bad Name"]) { $1 }), ("name with a slash", good.merging(["name": "a/b"]) { $1 }), ("no name", good.filter { $0.key != "name" }),
            ("chat as text", good.merging(["chat": "yes"]) { $1 }), ("no chat answer", good.filter { $0.key != "chat" }),
            ("negative ram", good.merging(["ram_reserve_mb": -1]) { $1 }), ("huge ram", good.merging(["ram_reserve_mb": 10_000_001]) { $1 }),
            ("fractional disk", good.merging(["disk_reserve_gb": 1.5]) { $1 }), ("unknown field", good.merging(["root": true]) { $1 }),
        ]
        for (label, body) in broken { XCTAssertThrowsError(try InstallRequest(body: data(body)), label) }
        for raw in ["", "{", "[]", "null"] { XCTAssertThrowsError(try InstallRequest(body: Data(raw.utf8)), raw) }
    }

    func testTheSuggestedRoomFollowsTheAgentsOwnRule() {
        XCTAssertEqual(InstallDefaults.ramReserveMb(totalMb: 16384), 4096)
        XCTAssertEqual(InstallDefaults.ramReserveMb(totalMb: 65536), 16384)
        XCTAssertEqual(InstallDefaults.ramReserveMb(totalMb: 4096), 2048, "never more than half of a small computer")
        XCTAssertEqual(InstallDefaults.diskReserveGb(totalGb: 494), 98)
        XCTAssertEqual(InstallDefaults.diskReserveGb(totalGb: 100), 30)
        XCTAssertEqual(InstallDefaults.diskReserveGb(totalGb: 40), 20, "never more than half of a small disk")
    }

    func testTheStepsComeInOrderAndTheChatStepOnlyWhenAsked() {
        XCTAssertEqual(InstallStep.plan(chat: false).map(\.id), ["check", "agent", "online"])
        XCTAssertEqual(InstallStep.plan(chat: true).map(\.id), ["check", "agent", "online", "chat"])
        XCTAssertTrue(InstallStep.plan(chat: true).allSatisfy { $0.state == .pending && $0.detail == nil })
    }
}
