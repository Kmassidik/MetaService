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

    func testAMissingLinuxProgramPointsToTheBuildScript() {
        let fix = "Run scripts/build-linux-helpers.sh on the parent's computer, then check again."
        for arch in ["x86_64", "aarch64"] {
            let result = RemoteVerify.run(facts: facts("os=Linux\narch=\(arch)\nuser=u\nport_9101=free\n"), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: "http://x:9102")
            XCTAssertEqual(row(result, "agent").fix, fix, arch)
        }
    }

    func testAMissingMacProgramKeepsItsOwnSentence() {
        let result = RemoteVerify.run(facts: facts(mac), fingerprint: "SHA256:abc", agentBuilds: [], parentURL: "http://x:9102")
        XCTAssertTrue(row(result, "agent").fix?.contains("darwin-arm64") ?? false)
        XCTAssertFalse(row(result, "agent").fix?.contains("build-linux-helpers") ?? true)
    }

    func testEveryMissingRequirementIsACrossThatBlocksAndSaysWhatToDo() {
        let poor = "os=Linux\narch=aarch64\nuser=u\nram_mb=2048\nkvm=no\ndisk_free_gb=5\nsudo=none\nport_9101=free\n"
        let result = RemoteVerify.run(facts: facts(poor), fingerprint: "SHA256:abc", agentBuilds: ["linux-arm64"], parentURL: "http://x:9102")
        XCTAssertFalse(result.canAdd)
        for id in ["memory", "disk", "vm_tool", "python"] {
            XCTAssertFalse(row(result, id).ok, id)
            XCTAssertFalse((row(result, id).fix ?? "").isEmpty, "\(id) must say what to do")
        }
        XCTAssertTrue(row(result, "admin").ok, "no sudo is not a failure: the engine goes in a folder")
        XCTAssertNil(row(result, "admin").fix)
    }

    func testAPassingRowHasNothingToFix() {
        let result = RemoteVerify.run(facts: facts(mac), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: "http://x:9102")
        XCTAssertTrue(result.requirements.allSatisfy { $0.fix == nil })
    }

    func testALinuxComputerWithoutKvmCanStillBeAddedAsContainersOnly() {
        let noKvm = linux.replacingOccurrences(of: "kvm=yes", with: "kvm=no").replacingOccurrences(of: "tool=incus\n", with: "tool=incus\ntool=python3\n")
        let result = RemoteVerify.run(facts: facts(noKvm), fingerprint: "SHA256:abc", agentBuilds: ["linux-x86_64"], parentURL: "http://x:9102")
        XCTAssertTrue(result.canAdd, "\(result.requirements.filter { !$0.ok })")
        XCTAssertTrue(row(result, "vm_support").ok)
        XCTAssertTrue(row(result, "vm_support").detail.contains("Containers only"))
        XCTAssertTrue(row(result, "vm_support").fix?.contains("modprobe") ?? false, "a tick that still says how to get full VMs: \(row(result, "vm_support").fix ?? "none")")
        let withKvm = RemoteVerify.run(facts: facts(noKvm.replacingOccurrences(of: "kvm=no", with: "kvm=yes")), fingerprint: "SHA256:abc", agentBuilds: ["linux-x86_64"], parentURL: "http://x:9102")
        XCTAssertTrue(row(withKvm, "vm_support").detail.contains("VMs and containers"))
    }

    func testALinuxComputerWithoutIncusIsToldHowToInstallItAndNothingMentionsATickBox() {
        let noIncus = linux.replacingOccurrences(of: "tool=incus\n", with: "tool=python3\n")
        let result = RemoteVerify.run(facts: facts(noIncus), fingerprint: "SHA256:abc", agentBuilds: ["linux-x86_64"], parentURL: "http://x:9102")
        XCTAssertFalse(result.canAdd)
        XCTAssertFalse(row(result, "vm_tool").ok)
        XCTAssertTrue(row(result, "vm_tool").fix!.contains("incus"))
        XCTAssertFalse(row(result, "vm_tool").detail.contains("tick"))
    }

    func testAReadyLinuxComputerCanBeAdded() {
        let ready = linux.replacingOccurrences(of: "tool=incus\n", with: "tool=incus\ntool=python3\n")
        let result = RemoteVerify.run(facts: facts(ready), fingerprint: "SHA256:abc", agentBuilds: ["linux-x86_64"], parentURL: "http://x:9102")
        XCTAssertTrue(result.canAdd, "\(result.requirements.filter { !$0.ok })")
    }

    func testOurOwnProgramOnThePortDoesNotBlockAndIsSaidToBeReplaced() {
        let ours = RemoteVerify.run(facts: facts(mac.replacingOccurrences(of: "port_9101=free", with: "port_9101=ours")), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: "http://192.168.100.40:9102")
        XCTAssertTrue(ours.canAdd)
        XCTAssertTrue(row(ours, "port").ok)
        XCTAssertTrue(row(ours, "port").detail.contains("replaces it"))
    }

    func testABusyPortBlocks() {
        let busy = RemoteVerify.run(facts: facts(mac.replacingOccurrences(of: "port_9101=free", with: "port_9101=busy")), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: "http://192.168.100.40:9102")
        XCTAssertFalse(busy.canAdd)
        XCTAssertFalse(row(busy, "port").ok)
        XCTAssertTrue(row(busy, "port").fix!.contains("9101"))
        let unknown = RemoteVerify.run(facts: facts(mac.replacingOccurrences(of: "port_9101=free\n", with: "")), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: "http://192.168.100.40:9102")
        XCTAssertTrue(unknown.canAdd, "a port that could not be checked does not block")
    }

    func testTheParentIsReachedThroughTheSshConnectionSoNothingHasToBeSetOnTheParent() {
        let result = RemoteVerify.run(facts: facts(mac), fingerprint: "SHA256:abc", agentBuilds: builds, parentURL: "http://127.0.0.1:9102")
        XCTAssertTrue(result.canAdd)
        XCTAssertTrue(row(result, "parent").ok)
        XCTAssertTrue(row(result, "parent").detail.contains("http://127.0.0.1:9102"))
        XCTAssertFalse(row(result, "parent").detail.contains("ROOT_AGENT_BIND"))
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
