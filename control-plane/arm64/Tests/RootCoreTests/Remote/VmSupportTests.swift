import XCTest
@testable import RootCore

/// "Can run workloads" on Linux: the four honest answers, because "no /dev/kvm" has several causes and only one of them is the BIOS.
final class VmSupportTests: XCTestCase {
    private func facts(_ text: String) -> RemoteFacts { RemoteProbe.parse(text)! }
    private let base = "os=Linux\narch=x86_64\nuser=build\nram_mb=32000\ndisk_free_gb=400\nport_9101=free\n"
    private let amdChip = "chip=AMD Ryzen 9 9950X 16-Core Processor\n"
    private let intelChip = "chip=Intel(R) Core(TM) i9-14900K\n"

    private func requirement(_ text: String) -> Requirement {
        RemoteVerify.run(facts: facts(base + text), fingerprint: "SHA256:a", agentBuilds: ["linux-x86_64"], parentURL: "http://x:9102")
            .requirements.first { $0.id == "vm_support" }!
    }

    func testWithKvmAndQemuTheRowIsAPlainTick() {
        let row = requirement("kvm=yes\nvirt=yes\nqemu=yes\n")
        XCTAssertTrue(row.ok)
        XCTAssertEqual(row.label, "Can run workloads")
        XCTAssertEqual(row.detail, "/dev/kvm is there: VMs and containers.")
        XCTAssertNil(row.fix, "nothing to do")
        XCTAssertNil(row.install)
    }

    func testWithoutKvmAndVirtualizationOffTheBiosIsNamed() {
        let row = requirement("kvm=no\nvirt=no\nqemu=yes\n")
        XCTAssertTrue(row.ok, "containers still work, so the computer can be added")
        XCTAssertEqual(row.detail, "Containers only: virtualization is off in the BIOS.")
        XCTAssertTrue(row.fix!.contains("SVM"), "the fix names AMD's setting: \(row.fix!)")
        XCTAssertTrue(row.fix!.contains("Intel VT"), "and Intel's: \(row.fix!)")
    }

    func testWithoutKvmButVirtualizationOnTheModuleIsNamedNeverTheBios() {
        let amd = requirement("kvm=no\nvirt=yes\nqemu=yes\n" + amdChip)
        XCTAssertEqual(amd.detail, "Containers only: virtualization is on, but the KVM module is not loaded.")
        XCTAssertTrue(amd.fix!.contains("sudo modprobe kvm_amd"), amd.fix!)
        XCTAssertFalse(amd.detail.contains("BIOS"), "the BIOS is already right, so it must not be blamed")
        XCTAssertFalse(amd.fix!.contains("BIOS"), amd.fix!)
        let intel = requirement("kvm=no\nvirt=yes\nqemu=yes\n" + intelChip)
        XCTAssertTrue(intel.fix!.contains("sudo modprobe kvm_intel"), intel.fix!)
    }

    func testAnUnknownChipIsToldBothModuleNames() {
        let fix = requirement("kvm=no\nvirt=yes\nqemu=yes\n").fix!
        XCTAssertTrue(fix.contains("kvm_amd") && fix.contains("kvm_intel"), fix)
    }

    func testAMachineThatCouldNotSayWhetherVirtualizationIsOnIsNeverToldItIsOff() {
        let row = requirement("kvm=no\nqemu=yes\n")
        XCTAssertEqual(row.detail, VmSupport.noKvm)
        XCTAssertFalse(row.detail.contains("BIOS"))
        XCTAssertTrue(row.fix!.contains("Check that virtualization is turned on"), row.fix!)
    }

    func testMissingQemuIsAddedToTheSentenceAndCanComeWithAMissingKvm() {
        let qemuOnly = requirement("kvm=yes\nvirt=yes\nqemu=no\n")
        // It must not claim "VMs and containers" while qemu is missing: the badge takes the first words of this sentence.
        XCTAssertEqual(qemuOnly.detail, VmSupport.kvmThereButNoQemu)
        XCTAssertFalse(qemuOnly.detail.contains("VMs and containers"))
        XCTAssertTrue(qemuOnly.fix!.contains("sudo apt install qemu-system-x86 ovmf"), qemuOnly.fix!)
        let both = requirement("kvm=no\nvirt=yes\nqemu=no\n" + amdChip)
        XCTAssertEqual(both.detail, "Containers only: virtualization is on, but the KVM module is not loaded. qemu is not installed.")
        XCTAssertTrue(both.fix!.contains("kvm_amd") && both.fix!.contains("qemu-system-x86"), both.fix!)
    }

    func testAnArmComputerGetsTheArmPackageNames() {
        let row = RemoteVerify.run(facts: RemoteProbe.parse("os=Linux\narch=aarch64\nuser=u\nkvm=no\nvirt=unknown\nqemu=no\ndisk_free_gb=400\nram_mb=32000\nport_9101=free\n")!,
                                   fingerprint: "SHA256:a", agentBuilds: ["linux-arm64"], parentURL: "http://x:9102").requirements.first { $0.id == "vm_support" }!
        XCTAssertTrue(row.fix!.contains("qemu-system-arm qemu-efi-aarch64"), row.fix!)
    }

    func testTheMacRowIsUnchanged() {
        let mac = RemoteVerify.run(facts: facts("os=Darwin\narch=arm64\nuser=mac\nport_9101=free\n"), fingerprint: "SHA256:a", agentBuilds: ["darwin-arm64"], parentURL: "http://x:9102")
        let apple = mac.requirements.first { $0.id == "vm_support" }!
        XCTAssertEqual([apple.label, apple.detail, apple.fix], ["Can run VMs", "Apple Silicon can.", nil])
    }
}
