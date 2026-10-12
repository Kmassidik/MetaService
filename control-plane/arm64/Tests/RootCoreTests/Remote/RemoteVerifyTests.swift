import XCTest
@testable import RootCore

final class RemoteVerifyTests: XCTestCase {
    private func facts(_ text: String) -> RemoteFacts { RemoteProbe.parse(text)! }
    private let mac = "os=Darwin\narch=arm64\nuser=mac\nversion=macOS 26\nchip=Apple M2\nram_mb=16384\ndisk_free_gb=242\ntool=container\ntool=python3\nsudo=password\nport_9101=free\n"
    private let linux = "os=Linux\narch=x86_64\nuser=build\nversion=Ubuntu 24.04\nram_mb=32000\nkvm=yes\ndisk_free_gb=400\ntool=incus\nsudo=none\nport_9101=free\n"
    private let builds: Set<String> = ["darwin-arm64"]

    private func row(_ result: RemoteVerification, _ id: String) -> Requirement { result.requirements.first { $0.id == id }! }

    func testAReadyMacCanBeAddedAndMayGetItsOwnUser() {
        let result = RemoteVerify.run(facts: facts(mac), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: "http://192.168.100.40:9102")
        XCTAssertTrue(result.canAdd)
        XCTAssertEqual(result.isolation, ["folder", "dedicated_user"])
        XCTAssertEqual(result.requirements.map(\.id), ["login", "system", "agent", "memory", "disk", "vm_support", "vm_tool", "python", "admin", "port", "parent"])
        XCTAssertTrue(result.requirements.allSatisfy(\.ok), "\(result.requirements.filter { !$0.ok })")
        XCTAssertTrue(row(result, "login").detail.contains("SHA256:abc"))
        XCTAssertEqual(result.system, "macOS 26 · Apple M2 · arm64")
    }

    func testWithoutAMatchingProgramNothingCanBeAdded() {
        let result = RemoteVerify.run(facts: facts(linux), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: "http://192.168.100.40:9102")
        XCTAssertFalse(result.canAdd)
        XCTAssertFalse(row(result, "agent").ok)
        XCTAssertTrue(row(result, "agent").detail.contains("linux-x86_64"))
        XCTAssertEqual(result.isolation, ["folder"], "no sudo, so only the folder box")
    }

    func testAMissingVmToolOrPythonOrLowMemoryDoesNotBlock() {
        let poor = "os=Linux\narch=aarch64\nuser=u\nram_mb=2048\nkvm=no\ndisk_free_gb=5\nsudo=none\nport_9101=free\n"
        let result = RemoteVerify.run(facts: facts(poor), fingerprint: "SHA256:abc", agentBuilds: ["linux-arm64"], parentURL: "http://x:9102")
        XCTAssertTrue(result.canAdd)
        for id in ["memory", "disk", "vm_support", "vm_tool", "python", "admin"] { XCTAssertFalse(row(result, id).ok, id); XCTAssertTrue(row(result, id).optional, id) }
        XCTAssertTrue(row(result, "vm_tool").detail.contains("Install the VM tool too"))
    }

    func testABusyPortBlocks() {
        let busy = RemoteVerify.run(facts: facts(mac.replacingOccurrences(of: "port_9101=free", with: "port_9101=busy")), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: "http://192.168.100.40:9102")
        XCTAssertFalse(busy.canAdd)
        XCTAssertFalse(row(busy, "port").ok)
        XCTAssertFalse(row(busy, "port").optional)
        let unknown = RemoteVerify.run(facts: facts(mac.replacingOccurrences(of: "port_9101=free\n", with: "")), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: "http://192.168.100.40:9102")
        XCTAssertTrue(unknown.canAdd, "a port that could not be checked does not block")
    }

    func testAParentThatOnlyListensOnItsOwnComputerBlocks() {
        let result = RemoteVerify.run(facts: facts(mac), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: nil)
        XCTAssertFalse(result.canAdd)
        XCTAssertFalse(row(result, "parent").ok)
        XCTAssertFalse(row(result, "parent").optional)
        XCTAssertTrue(row(result, "parent").detail.contains("ROOT_AGENT_BIND"))
    }

    func testAnUnsupportedSystemBlocks() {
        for text in ["os=FreeBSD\narch=amd64\n", "os=Linux\narch=riscv64\n", "os=Darwin\narch=i386\n"] {
            let result = RemoteVerify.run(facts: facts(text), fingerprint: "SHA256:abc", agentBuilds: ["freebsd-amd64", "linux-riscv64", "darwin-i386"], parentURL: "http://x:9102")
            XCTAssertFalse(row(result, "system").ok, text)
            XCTAssertFalse(result.canAdd, text)
        }
    }

    func testAnIntelMacCannotRunVmsButCanStillBeListed() {
        let intel = RemoteVerify.run(facts: facts("os=Darwin\narch=x86_64\nuser=u\nport_9101=free\n"), fingerprint: "SHA256:abc", agentBuilds: ["darwin-x86_64"], parentURL: "http://x:9102")
        XCTAssertFalse(row(intel, "vm_support").ok)
        XCTAssertTrue(row(intel, "vm_support").detail.contains("Apple Silicon"))
    }
}
