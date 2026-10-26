import XCTest
import MSCore
@testable import RootCore

/// A re-check of a machine that is already added: the request names it, and the address and host key come from its record — never from the request.
final class RemoteLoginTargetTests: XCTestCase {
    private let fingerprint = "SHA256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukWY"
    private let record = StoredMachine(host: "192.168.100.40", port: 22, user: "kurnia", fingerprint: "SHA256:record")

    func testATypedAddressResolvesWithoutARecord() throws {
        let target = try RemoteTarget(host: "10.0.0.5", port: 2222, user: "build")
        let resolved = RemoteLoginTarget.typed(target, fingerprint: fingerprint).resolved(login: .password("x"), stored: nil)
        XCTAssertEqual(resolved?.target, target)
        XCTAssertEqual(resolved?.fingerprint, fingerprint)
    }

    func testAStoredMachineResolvesToItsOwnAddressAndHostKey() {
        let resolved = RemoteLoginTarget.stored(machine: "office-mini").resolved(login: .parentKey, stored: record)
        XCTAssertEqual(resolved?.target.host, "192.168.100.40")
        XCTAssertEqual(resolved?.target.port, 22)
        XCTAssertEqual(resolved?.target.user, "kurnia")
        XCTAssertEqual(resolved?.fingerprint, "SHA256:record")
        XCTAssertEqual(resolved?.login, .parentKey)
    }

    func testAMachineWithNoRecordCannotBeChecked() {
        XCTAssertNil(RemoteLoginTarget.stored(machine: "unknown").resolved(login: .password("x"), stored: nil), "unknown, or never added over SSH")
        XCTAssertNil(RemoteLoginTarget.stored(machine: "office-mini").resolved(login: .password("x"),
                                                                              stored: StoredMachine(host: "-oProxyCommand=x", port: 22, user: "kurnia", fingerprint: fingerprint)),
                     "a record that is not a plain address is never handed to ssh")
    }

    func testTheMachineFieldIsAMachineName() throws {
        let data = try JSONSerialization.data(withJSONObject: ["machine": "office-mini", "password": "x"])
        XCTAssertEqual(try VerifyRequest(body: data).target.storedMachine, "office-mini")
        XCTAssertNil(try VerifyRequest(body: try JSONSerialization.data(withJSONObject: ["host": "10.0.0.5", "user": "u", "password": "x", "fingerprint": fingerprint])).target.storedMachine)
    }
}
