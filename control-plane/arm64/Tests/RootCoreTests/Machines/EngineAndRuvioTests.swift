import XCTest
@testable import RootCore

final class EngineAndRuvioTests: XCTestCase {
    private func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    private func heartbeat(agentVersion: Any? = nil, engine: Any? = nil) -> [String: Any] {
        var body = RequestsTests.goodHeartbeat()
        var facts = body["facts"] as! [String: Any]
        if let agentVersion { facts["agent_version"] = agentVersion }
        if let engine { facts["engine"] = engine }
        body["facts"] = facts
        return body
    }

    func testTheHelperVersionAndTheEngineAreReadWhenTheHelperSaysThem() throws {
        let beat = try HeartbeatRequest(body: data(heartbeat(agentVersion: "0.2.0", engine: ["name": "apple-container", "version": "1.5.0", "ready": true])))
        XCTAssertEqual(beat.facts.agentVersion, "0.2.0")
        XCTAssertEqual(beat.facts.engine, EngineReport(name: "apple-container", version: "1.5.0", ready: true))
    }

    func testAnOlderHelperThatSaysNothingGivesNothingAndNothingIsMadeUp() throws {
        let beat = try HeartbeatRequest(body: data(heartbeat()))
        XCTAssertNil(beat.facts.agentVersion)
        XCTAssertNil(beat.facts.engine)
        let unknownVersion = try HeartbeatRequest(body: data(heartbeat(engine: ["name": "incus", "ready": false])))
        XCTAssertEqual(unknownVersion.facts.engine, EngineReport(name: "incus", version: nil, ready: false))
        XCTAssertEqual(try HeartbeatRequest(body: data(heartbeat(engine: ["name": "incus", "version": NSNull(), "ready": false]))).facts.engine?.version, nil)
    }

    func testTheHelperBuildIsReadWhenItIsSixtyFourLowercaseHexDigitsAndRefusedOtherwise() throws {
        func beat(_ build: Any) -> [String: Any] {
            var body = heartbeat()
            var facts = body["facts"] as! [String: Any]
            facts["agent_build"] = build
            body["facts"] = facts
            return body
        }
        let good = String(repeating: "0f", count: 32)
        XCTAssertEqual(try HeartbeatRequest(body: data(beat(good))).facts.agentBuild, good)
        XCTAssertNil(try HeartbeatRequest(body: data(heartbeat())).facts.agentBuild)
        XCTAssertNil(try HeartbeatRequest(body: data(beat(NSNull()))).facts.agentBuild)
        let bad: [Any] = ["", "abc", good.uppercased(), good + "0", String(good.dropLast()), 5, ["a"], "<script>" + String(repeating: "a", count: 56)] + MachineSettingsPatchTests.hostile
        for item in bad { XCTAssertThrowsError(try HeartbeatRequest(body: data(beat(item))), "\(item)") }
    }

    func testTheEngineAlwaysSendsItsVersionEvenWhenItIsNull() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(EngineReport(name: "incus", version: nil, ready: true))) as! [String: Any]
        XCTAssertTrue(json["version"] is NSNull)
        XCTAssertEqual(json["name"] as? String, "incus")
    }

    func testHostileStringsInTheNewFactsAreRefused() {
        for text in MachineSettingsPatchTests.hostile where !text.isEmpty {
            XCTAssertThrowsError(try HeartbeatRequest(body: data(heartbeat(agentVersion: text))), "agent_version \(text.prefix(20))")
            XCTAssertThrowsError(try HeartbeatRequest(body: data(heartbeat(engine: ["name": text, "ready": true]))), "engine name \(text.prefix(20))")
            XCTAssertThrowsError(try HeartbeatRequest(body: data(heartbeat(engine: ["name": "incus", "version": text, "ready": true]))), "engine version \(text.prefix(20))")
        }
        XCTAssertThrowsError(try HeartbeatRequest(body: data(heartbeat(agentVersion: ""))))
        XCTAssertThrowsError(try HeartbeatRequest(body: data(heartbeat(agentVersion: 5))))
        XCTAssertThrowsError(try HeartbeatRequest(body: data(heartbeat(agentVersion: ["a"]))))
    }

    func testTheEngineObjectIsStrict() {
        let bad: [Any] = [["name": "incus"], ["ready": true], ["name": "incus", "ready": "yes"], ["name": "incus", "ready": 1], ["name": "incus", "ready": true, "path": "/bin/sh"], "incus", ["incus"], 5]
        for item in bad { XCTAssertThrowsError(try HeartbeatRequest(body: data(heartbeat(engine: item))), "\(item)") }
    }

    func testRuvioStateFollowsWhatIsInstalledAndPinned() {
        XCTAssertEqual(RuvioStatus.make(installed: nil, pinned: nil, going: nil).state, .unavailable)
        XCTAssertEqual(RuvioStatus.make(installed: nil, pinned: "0.4.0", going: nil).state, .off)
        XCTAssertEqual(RuvioStatus.make(installed: "0.4.0", pinned: "0.4.0", going: nil).state, .on)
        XCTAssertEqual(RuvioStatus.make(installed: "0.3.0", pinned: "0.4.0", going: nil).state, .outdated)
        XCTAssertEqual(RuvioStatus.make(installed: "0.3.0", pinned: nil, going: nil).state, .on, "with nothing pinned there is nothing to be behind")
    }

    func testACommandThatIsGoingWinsOverWhatWasLastReported() {
        XCTAssertEqual(RuvioStatus.make(installed: nil, pinned: "0.4.0", going: .install).state, .installing)
        XCTAssertEqual(RuvioStatus.make(installed: "0.4.0", pinned: "0.4.0", going: .uninstall).state, .removing)
    }

    func testRuvioSendsNullForWhatIsNotThere() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(RuvioStatus.make(installed: nil, pinned: nil, going: nil))) as! [String: Any]
        XCTAssertTrue(json["installed"] is NSNull)
        XCTAssertTrue(json["pinned"] is NSNull)
        XCTAssertEqual(json["state"] as? String, "unavailable")
    }
}
