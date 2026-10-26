import XCTest
import MSCore
@testable import RootCore

final class RemoteRequestsTests: XCTestCase {
    private let fingerprint = "SHA256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukWY"
    private func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
    private func verify(_ changes: [String: Any] = [:]) throws -> VerifyRequest {
        try VerifyRequest(body: data(["host": "192.168.100.40", "user": "kurnia", "password": "secret", "fingerprint": fingerprint].merging(changes) { $1 }))
    }

    func testAProbeNeedsOnlyAHost() throws {
        XCTAssertEqual(try ProbeRequest(body: data(["host": "10.0.0.5"])).target.port, 22)
        XCTAssertEqual(try ProbeRequest(body: data(["host": "10.0.0.5", "port": 2222])).target.port, 2222)
        for bad in [["host": "-oProxyCommand=x"], ["host": ""], ["host": "10.0.0.5", "port": 0], ["host": "10.0.0.5", "port": "22"], ["host": "10.0.0.5", "user": "root"], [:]] as [[String: Any]] {
            XCTAssertThrowsError(try ProbeRequest(body: data(bad)), "\(bad)")
        }
    }

    func testAPasswordLoginIsRead() throws {
        let request = try verify()
        XCTAssertEqual(request.login, .password("secret"))
        guard case .typed(let target, let fingerprint) = request.target else { return XCTFail("a typed address") }
        XCTAssertEqual(target.user, "kurnia")
        XCTAssertEqual(fingerprint, self.fingerprint)
    }

    func testTheParentsKeyCanBeUsedInsteadOfAPassword() throws {
        XCTAssertEqual(try verify(["password": NSNull(), "use_key": true]).login, .parentKey)
        XCTAssertEqual(try VerifyRequest(body: data(["host": "10.0.0.5", "user": "u", "use_key": true, "fingerprint": fingerprint])).login, .parentKey)
    }

    func testExactlyOneWayToLogInIsRequired() {
        XCTAssertThrowsError(try verify(["use_key": true]), "both")
        XCTAssertThrowsError(try verify(["password": ""]), "neither")
        XCTAssertThrowsError(try VerifyRequest(body: data(["host": "10.0.0.5", "user": "u", "fingerprint": fingerprint])), "neither")
    }

    func testABadFingerprintOrUserOrFieldIsRefused() {
        for bad in [["fingerprint": "SHA256:short"], ["fingerprint": "MD5:aa"], ["user": "-oProxyCommand=x"], ["user": ""], ["password": String(repeating: "a", count: 257)], ["extra": 1], ["use_key": "yes"]] as [[String: Any]] {
            XCTAssertThrowsError(try verify(bad), "\(bad)")
        }
    }

    func testAPasswordIsNeverPartOfTheTextOfARefusal() {
        for bad in [["user": ""], ["fingerprint": "nope"], ["extra": 1]] as [[String: Any]] {
            XCTAssertThrowsError(try verify(bad)) { XCTAssertFalse("\($0)".contains("secret"), "\($0)") }
        }
    }

    // MARK: check again, on a machine that is already added

    func testARecheckNamesTheMachineAndCarriesOnlyTheLogin() throws {
        let request = try VerifyRequest(body: data(["machine": "office-mini", "password": "secret"]))
        XCTAssertEqual(request.target, .stored(machine: "office-mini"))
        XCTAssertEqual(request.login, .password("secret"))
        XCTAssertEqual(try VerifyRequest(body: data(["machine": "office-mini", "use_key": true])).login, .parentKey)
    }

    func testARecheckTakesAnAddressOrAMachineNeverBoth() {
        for bad in [["machine": "office-mini", "host": "192.168.100.40"], ["machine": "office-mini", "user": "kurnia"],
                    ["machine": "office-mini", "fingerprint": fingerprint], ["machine": "Bad Name", "password": "x"],
                    ["machine": "", "password": "x"], ["machine": "office-mini"]] as [[String: Any]] {
            XCTAssertThrowsError(try VerifyRequest(body: data(bad)), "\(bad)")
        }
    }

    func testAFixForARecheckCarriesTheMachineThePartAndThePassword() throws {
        let request = try RemoteFixRequest(body: data(["machine": "office-mini", "password": "secret", "fix": "autostart", "sudo_password": "sudopw"]))
        XCTAssertEqual(request.target, .stored(machine: "office-mini"))
        XCTAssertEqual(request.login, .password("secret"))
        XCTAssertEqual(request.part, .autostart)
        XCTAssertEqual(String(decoding: request.sudoPassword.standardInput(), as: UTF8.self), "sudopw\n")
        XCTAssertThrowsError(try RemoteFixRequest(body: data(["machine": "office-mini", "password": "x", "fix": "vm_tool", "host": "10.0.0.5"])))
    }

    // MARK: add and plan

    private func add(_ changes: [String: Any] = [:]) throws -> RemoteAddRequest {
        try RemoteAddRequest(body: data(["host": "192.168.100.40", "user": "kurnia", "use_key": true, "fingerprint": fingerprint, "name": "office-mini"].merging(changes) { $1 }))
    }

    func testAnAddRequestHasTheLoginTheNameAndSafeDefaults() throws {
        let request = try add()
        XCTAssertEqual(request.login.login, .parentKey)
        XCTAssertEqual(request.choices.name, "office-mini")
        XCTAssertTrue(request.choices.installKey)
        XCTAssertFalse(request.choices.chat)
        XCTAssertNil(request.choices.box)
    }

    func testAScreenChoiceIsAnUnknownFieldNow() {
        XCTAssertThrowsError(try add(["allow_screen": true]))
    }

    func testAnAddRequestCarriesTheChoicesAndTheMachineSettings() throws {
        let request = try add(["box": "/opt/x/box", "ssh_dir": "/opt/x/.ssh", "agent_port": 9111, "install_key": false, "chat": true, "ram_reserve_mb": 4096, "labels": ["office"]])
        XCTAssertEqual([request.choices.box, request.choices.sshDirectory], ["/opt/x/box", "/opt/x/.ssh"])
        XCTAssertEqual(request.choices.agentPort, 9111)
        XCTAssertEqual([request.choices.installKey, request.choices.chat], [false, true])
        XCTAssertThrowsError(try add(["install_vm_tool": true]), "installing the VM tool is its own request now (/api/remote/fix), not a choice of the install")
        XCTAssertEqual(request.choices.settings.ramReserveMb, 4096)
        let options = try request.choices.options(home: "/Users/kurnia", engine: "apple", rootURL: "http://192.168.100.40:9102")
        XCTAssertEqual([options.box, options.sshDirectory, options.rootURL], ["/opt/x/box", "/opt/x/.ssh", "http://192.168.100.40:9102"])
        XCTAssertEqual(try add().choices.options(home: "/Users/kurnia", engine: "apple", rootURL: "u").box, "/Users/kurnia/metaservice-box")
    }

    func testABadNameOrPathOrPortOrFieldInAnAddRequestIsRefused() throws {
        for bad in [["name": "Bad Name"], ["name": ""], ["agent_port": 80], ["agent_port": "9101"], ["install_key": "yes"], ["extra": 1], ["password": "x"], ["use_key": false]] as [[String: Any]] {
            XCTAssertThrowsError(try add(bad), "\(bad)")
        }
        for bad in [["box": "/a b"], ["box": "relative"], ["box": "/a/../b"], ["ssh_dir": "/a;b"], ["ssh_dir": "~/.ssh"]] as [[String: Any]] {
            XCTAssertThrowsError(try add(bad), "refused at the request, before any install starts: \(bad)")
        }
    }

    func testAPlanRequestNeedsNoLoginAndChecksTheHomeFolder() throws {
        let body: [String: Any] = ["host": "192.168.100.40", "home": "/Users/kurnia", "os": "Darwin", "name": "office-mini"]
        let request = try PlanRequest(body: data(body))
        XCTAssertTrue(request.isMac)
        XCTAssertEqual(request.home, "/Users/kurnia")
        XCTAssertFalse(try PlanRequest(body: data(body.merging(["os": "Linux"]) { $1 })).isMac)
        for bad in [["home": "relative"], ["home": "/a b"], ["os": "Windows"], ["password": "x"], ["fingerprint": fingerprint]] as [[String: Any]] {
            XCTAssertThrowsError(try PlanRequest(body: data(body.merging(bad) { $1 })), "\(bad)")
        }
    }

    func testARemoveRequestNeedsALoginOrAChoiceToOnlyForget() throws {
        XCTAssertEqual(try RemoteRemoveRequest(body: data(["password": "x"])).login, .password("x"))
        XCTAssertEqual(try RemoteRemoveRequest(body: data(["use_key": true])).login, .parentKey)
        let forget = try RemoteRemoveRequest(body: data(["forget_only": true]))
        XCTAssertTrue(forget.forgetOnly)
        XCTAssertNil(forget.login)
        for bad in [[:], ["password": "x", "use_key": true], ["forget_only": true, "password": "x"], ["forget_only": true, "use_key": true], ["host": "x"], ["password": ""]] as [[String: Any]] {
            XCTAssertThrowsError(try RemoteRemoveRequest(body: data(bad)), "\(bad)")
        }
    }
}
