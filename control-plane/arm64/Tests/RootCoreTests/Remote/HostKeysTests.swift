import XCTest
@testable import RootCore

final class HostKeysTests: XCTestCase {
    /// What ssh-keyscan and ssh-keygen really printed for a test server.
    private let scan = """
    # 127.0.0.1:64562 SSH-2.0-OpenSSH_10.3
    [127.0.0.1]:64562 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKRUY6gfhYEHCBqe
    """
    private let keygen = "256 SHA256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukWY [127.0.0.1]:64562 (ED25519)\n"

    func testTheKeyLineIsPickedAndTheCommentIsIgnored() {
        XCTAssertEqual(HostKeys.chooseKey(scanOutput: scan), "[127.0.0.1]:64562 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKRUY6gfhYEHCBqe")
    }

    func testEd25519IsPreferredOverEcdsaAndRsa() {
        let all = "h ssh-rsa AAAArsa\nh ecdsa-sha2-nistp256 AAAAecdsa\nh ssh-ed25519 AAAAed\n"
        XCTAssertEqual(HostKeys.chooseKey(scanOutput: all), "h ssh-ed25519 AAAAed")
        XCTAssertEqual(HostKeys.chooseKey(scanOutput: "h ssh-rsa AAAArsa\nh ecdsa-sha2-nistp256 AAAAecdsa\n"), "h ecdsa-sha2-nistp256 AAAAecdsa")
    }

    func testOddLinesAreNeverTrusted() {
        for text in ["", "# only a comment", "h ssh-dss AAAA", "h ssh-ed25519", "h ssh-ed25519 AAAA extra", "-h ssh-ed25519 AAAA", "h ssh-ed25519 AA;AA", "h ssh-ed25519 AA AA"] {
            XCTAssertNil(HostKeys.chooseKey(scanOutput: text), text)
        }
    }

    func testTheFingerprintIsReadFromWhatSshKeygenSays() {
        XCTAssertEqual(HostKeys.parseFingerprint(keygenOutput: keygen), "SHA256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukWY")
        XCTAssertNil(HostKeys.parseFingerprint(keygenOutput: "not a fingerprint"))
        XCTAssertNil(HostKeys.parseFingerprint(keygenOutput: "256 MD5:aa:bb host (ED25519)"))
    }

    func testTheFingerprintIsWorkedOutHereAndAgreesWithSshKeygen() {
        let line = "[127.0.0.1]:64562 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKRUY6gfhYEHCBqePWrHTNKz2QlJ01FtVVV+kaWAuPPR"
        XCTAssertEqual(HostKeys.fingerprint(ofKeyLine: line), "SHA256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukWY")
        XCTAssertNil(HostKeys.fingerprint(ofKeyLine: "not a key line"))
        XCTAssertNil(HostKeys.fingerprint(ofKeyLine: "h ssh-ed25519 ***notbase64***"))
    }

    func testAComputerIsNamedTheWayKnownHostsNamesIt() {
        XCTAssertEqual(HostKeys.spec(host: "192.168.100.40", port: 22), "192.168.100.40")
        XCTAssertEqual(HostKeys.spec(host: "127.0.0.1", port: 64562), "[127.0.0.1]:64562")
    }

    func testOnlyAWellFormedFingerprintPasses() {
        XCTAssertTrue(HostKeys.isFingerprint("SHA256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukWY"))
        for text in ["", "SHA256:short", "sha256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukWY", "SHA256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukW;", "SHA256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukWYY"] {
            XCTAssertFalse(HostKeys.isFingerprint(text), text)
        }
    }
}
