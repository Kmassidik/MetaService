import XCTest
import RootCore
@testable import RootStore

final class RemoteMachineStoreTests: XCTestCase {
    private func store() throws -> RemoteMachineStore {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        return RemoteMachineStore(database)
    }

    private let mini = RemoteMachine(machine: "office-mini", host: "192.168.100.50", sshPort: 22, sshUser: "kurnia", fingerprint: "SHA256:abc", level: "folder", box: "/Users/kurnia/metaservice-box",
                                     sshDirectory: "/Users/kurnia/.ssh", agentPort: 9101, engine: "apple", keyName: "machine:office-mini", keyFile: "/Users/kurnia/.ssh/authorized_keys",
                                     keyMarker: "metaservice-office-mini", keyFileCreated: false, sshDirCreated: true)

    func testAMachineIsKeptWithEverythingNeededToRemoveItExactly() throws {
        let machines = try store()
        try machines.save(mini, now: Date())
        XCTAssertEqual(try machines.get("office-mini"), mini)
        XCTAssertEqual(try machines.all(), [mini])
    }

    func testAMachineWithoutAKeyIsKeptToo() throws {
        let machines = try store()
        let plain = RemoteMachine(machine: "plain", host: "10.0.0.5", sshPort: 2222, sshUser: "u", fingerprint: "SHA256:x", level: "folder", box: "/b", sshDirectory: "/s", agentPort: 9111, engine: "incus",
                                  keyName: nil, keyFile: nil, keyMarker: nil, keyFileCreated: false, sshDirCreated: false)
        try machines.save(plain, now: Date())
        XCTAssertEqual(try machines.get("plain"), plain)
    }

    func testAnUnknownMachineIsNil() throws {
        XCTAssertNil(try store().get("nobody"))
        XCTAssertNil(try store().stored("nobody"), "a machine that was not added over SSH has no re-check target")
    }

    func testTheReCheckTargetIsTheRecordWithoutItsKeyAndBox() throws {
        let machines = try store()
        try machines.save(mini, now: Date())
        XCTAssertEqual(try machines.stored("office-mini"), StoredMachine(host: "192.168.100.50", port: 22, user: "kurnia", fingerprint: "SHA256:abc"))
    }

    func testRemovingForgetsItAndCanBeRepeated() throws {
        let machines = try store()
        try machines.save(mini, now: Date())
        try machines.remove("office-mini")
        XCTAssertNil(try machines.get("office-mini"))
        XCTAssertNoThrow(try machines.remove("office-mini"))
        XCTAssertEqual(try machines.all(), [])
    }
}
