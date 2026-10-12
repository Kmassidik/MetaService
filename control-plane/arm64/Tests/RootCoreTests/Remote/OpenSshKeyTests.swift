import XCTest
@testable import RootCore

final class OpenSshKeyTests: XCTestCase {
    private func run(_ program: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    private func file(_ text: String) throws -> String {
        let folder = NSTemporaryDirectory() + "ms-key-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let path = folder + "/key"
        FileManager.default.createFile(atPath: path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
        addTeardownBlock { try? FileManager.default.removeItem(atPath: folder) }
        return path
    }

    func testOpenSshAcceptsTheKeyAndItsPublicHalfMatches() throws {
        let pair = OpenSshKey.generateEd25519(comment: "metaservice-parent")
        let path = try file(pair.privateKey)
        let derived = try run("/usr/bin/ssh-keygen", ["-y", "-f", path])
        XCTAssertEqual(derived.status, 0, "ssh-keygen could not read the private key")
        XCTAssertEqual(derived.output.trimmingCharacters(in: .whitespacesAndNewlines), pair.publicKey, "the public half OpenSSH derives from the private key is the one we gave out")
        XCTAssertTrue(pair.publicKey.hasSuffix(" metaservice-parent"))
    }

    func testTheFingerprintWeWorkOutMatchesSshKeygens() throws {
        let pair = OpenSshKey.generateEd25519(comment: "c")
        let path = try file(pair.publicKey + "\n")
        let said = try run("/usr/bin/ssh-keygen", ["-lf", path]).output
        XCTAssertEqual(HostKeys.fingerprint(ofKeyLine: "host " + pair.publicKey.split(separator: " ").prefix(2).joined(separator: " ")), HostKeys.parseFingerprint(keygenOutput: said))
    }

    func testEveryKeyIsNewAndTheTextLooksLikeAnOpenSshKey() {
        let first = OpenSshKey.generateEd25519(comment: "c"), second = OpenSshKey.generateEd25519(comment: "c")
        XCTAssertNotEqual(first.privateKey, second.privateKey)
        XCTAssertNotEqual(first.publicKey, second.publicKey)
        XCTAssertTrue(first.privateKey.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----\n"))
        XCTAssertTrue(first.privateKey.hasSuffix("-----END OPENSSH PRIVATE KEY-----\n"))
        XCTAssertTrue(first.publicKey.hasPrefix("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA"))
    }

    func testThePrivateKeyIsNotInThePublicLine() {
        let pair = OpenSshKey.generateEd25519(comment: "c")
        let body = pair.privateKey.split(separator: "\n").dropFirst().dropLast().joined()
        XCTAssertFalse(pair.publicKey.contains(String(body.prefix(40))))
    }
}
