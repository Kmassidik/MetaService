import XCTest
@testable import RootStore

final class RemoteKeyStoreTests: XCTestCase {
    private func store() throws -> RemoteKeyStore {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        return RemoteKeyStore(database)
    }

    func testAKeyIsKeptAndReadBack() throws {
        let keys = try store()
        XCTAssertNil(try keys.get("parent"))
        try keys.addIfMissing(RemoteKey(name: "parent", publicKey: "ssh-ed25519 AAAA parent", privateSealed: "sealed-1"), now: Date())
        XCTAssertEqual(try keys.get("parent"), RemoteKey(name: "parent", publicKey: "ssh-ed25519 AAAA parent", privateSealed: "sealed-1"))
    }

    func testAKeyThatExistsIsNeverReplaced() throws {
        let keys = try store()
        try keys.addIfMissing(RemoteKey(name: "parent", publicKey: "first", privateSealed: "sealed-1"), now: Date())
        try keys.addIfMissing(RemoteKey(name: "parent", publicKey: "second", privateSealed: "sealed-2"), now: Date())
        XCTAssertEqual(try keys.get("parent")?.publicKey, "first")
    }

    func testAKeyCanBeRemoved() throws {
        let keys = try store()
        try keys.addIfMissing(RemoteKey(name: "machine-a", publicKey: "k", privateSealed: "s"), now: Date())
        try keys.remove("machine-a")
        XCTAssertNil(try keys.get("machine-a"))
        XCTAssertNoThrow(try keys.remove("machine-a"))
    }
}
