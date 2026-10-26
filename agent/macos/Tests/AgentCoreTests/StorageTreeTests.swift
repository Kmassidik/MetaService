import XCTest
@testable import AgentCore

final class StorageTreeTests: XCTestCase {
    private func entry(_ name: String, _ type: StorageEntryType = .dir, _ bytes: UInt64 = 0) -> StorageEntry {
        StorageEntry(name: name, type: type, bytes: bytes, files: type == .file ? 1 : 0)
    }

    private func attach(_ parent: StorageEntry, _ children: [StorageEntry]) {
        let rest = StorageEntry.rest()
        for child in children { parent.attach(child, floor: 0, rest: rest) }
        parent.finish(rest: rest)
    }

    func testClassificationAndReclaimFollowLinuxRules() {
        let root = entry("/")
        let projects = entry("projects")
        let app = entry("app")
        app.noteChild(named: "Cargo.toml")
        let target = entry("target", .dir, 600)
        let debug = entry("debug", .dir, 500)
        attach(target, [debug])
        attach(app, [target, entry("Cargo.toml", .file, 1)])
        let web = entry("web")
        web.noteChild(named: "package.json")
        let modules = entry("node_modules", .dir, 300)
        let git = entry(".git", .dir, 200)
        attach(web, [modules, git, entry("package.json", .file, 1)])
        attach(projects, [app, web])
        attach(root, [projects, entry(".cache", .dir, 100), entry("incus", .dir, 400)])

        StorageClassifier.classify(root)
        XCTAssertEqual(projects.kind, .code)
        XCTAssertEqual(target.reclaim, .buildOutput)
        XCTAssertEqual(debug.reclaim, .buildOutput)
        XCTAssertEqual(modules.kind, .cache)
        XCTAssertEqual(modules.reclaim, .reinstallable)
        XCTAssertEqual(git.kind, .git)
        XCTAssertEqual(root.children.first { $0.name == ".cache" }?.reclaim, .regenerable)
        XCTAssertEqual(root.children.first { $0.name == "incus" }?.kind, .vms)
    }

    func testUnknownTopFolderUsesDominantKindAndTargetNeedsManifest() {
        let root = entry("/")
        let world = entry("world")
        let git = entry(".git", .dir, 400)
        git.noteChild(named: "objects")
        git.noteChild(named: "refs")
        git.noteChild(named: "HEAD")
        attach(world, [git, entry("target", .dir, 200)])
        attach(root, [world])
        StorageClassifier.classify(root)
        XCTAssertEqual(world.kind, .git)
        XCTAssertNil(world.children.first { $0.name == "target" }?.reclaim)
    }

    func testSmallEntriesAndDepthFoldIntoRestWithoutLosingTotals() throws {
        let root = entry("/", .dir, 16)
        let notes = entry("notes", .dir, 8)
        attach(notes, (0..<20).map { entry("note-\($0)", .file, 2) })
        attach(root, [notes])
        let total = root.bytes
        StorageTree.fit(root, max: 2)
        let rest = try XCTUnwrap(root.children.first)
        XCTAssertEqual(rest.type, .rest)
        XCTAssertEqual(rest.files, 20)
        XCTAssertEqual(rest.items, 1)
        XCTAssertEqual(root.bytes, total)
    }

    func testNodeLimitCompactionPreservesBytesAndFileCounts() {
        let root = entry("/")
        for group in 0..<6 {
            let folder = entry("dir-\(group)")
            attach(folder, (0..<10).map { entry("file-\($0)", .file, UInt64(group * 10 + $0 + 1) * 4096) })
            attach(root, [folder])
        }
        let total = root.bytes
        let files = root.files
        XCTAssertGreaterThan(root.count, 20)
        StorageTree.fit(root, max: 20)
        XCTAssertLessThanOrEqual(root.count, 20)
        XCTAssertEqual(root.bytes, total)
        XCTAssertEqual(root.files, files)
        XCTAssertEqual(root.children.reduce(UInt64(0)) { $0 + $1.bytes }, total)
    }

    func testContractNodeLimitIsNeverExceeded() {
        let root = entry("/")
        attach(root, (0..<(StorageTree.maxNodes + 10)).map { entry("file-\($0)", .file, UInt64($0 + 1)) })
        let total = root.bytes
        let files = root.files
        StorageTree.fit(root)
        XCTAssertLessThanOrEqual(root.count, StorageTree.maxNodes)
        XCTAssertEqual(root.bytes, total)
        XCTAssertEqual(root.files, files)
    }

    func testFlattenUsesEarlierDirectoryParentsAndLargestFirstSiblings() throws {
        let root = entry("/")
        attach(root, [entry("small", .dir, 10), entry("large", .dir, 30), entry("middle", .dir, 20)])
        StorageClassifier.classify(root)
        let nodes = StorageTree.flatten(root)
        XCTAssertEqual(nodes.map(\.name), ["/", "large", "middle", "small"])
        XCTAssertEqual(nodes[0].parent, -1)
        XCTAssertEqual(nodes[0].type, .dir)
        for (place, node) in nodes.enumerated().dropFirst() {
            XCTAssertTrue((0..<place).contains(node.parent))
            XCTAssertEqual(nodes[node.parent].type, .dir)
        }
    }

    func testContractEncodingIncludesNullsAndExactKeys() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let answer = StorageAnswer(scanning: false, progress: nil, error: nil, map: nil)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(answer)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["scanning", "progress", "error", "map"])
        XCTAssertTrue(object["progress"] is NSNull)
        XCTAssertTrue(object["error"] is NSNull)
        XCTAssertTrue(object["map"] is NSNull)

        let node = StorageNode(parent: -1, name: "/", type: .dir, bytes: 0, files: 0, items: 0, kind: .other, reclaim: nil, modified: nil)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(node)) as? [String: Any])
        XCTAssertEqual(Set(encoded.keys), ["parent", "name", "type", "bytes", "files", "items", "kind", "reclaim", "modified"])
        XCTAssertTrue(encoded["reclaim"] is NSNull)
        XCTAssertTrue(encoded["modified"] is NSNull)
    }
}
