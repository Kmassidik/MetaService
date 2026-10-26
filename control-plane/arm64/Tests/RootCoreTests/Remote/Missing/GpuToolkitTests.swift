import XCTest
@testable import RootCore

final class GpuToolkitTests: XCTestCase {
    private func facts(_ text: String) -> RemoteFacts { RemoteProbe.parse(text)! }
    private let home = "/home/build/metaservice-box"
    private let head = "os=Linux\narch=x86_64\nuser=build\nram_mb=32000\nkvm=no\ndisk_free_gb=400\npkg=apt\nsudo=password\ntool=incus\ntool=python3\nport_9101=free\n"
    private let card = "nvidia_gpu=NVIDIA GeForce RTX 5090\n"

    private func verify(_ text: String) -> RemoteVerification {
        RemoteVerify.run(facts: facts(text), fingerprint: "SHA256:a", agentBuilds: ["linux-x86_64"], parentURL: "http://x:9102")
    }

    private func row(_ text: String) -> Requirement? { verify(text).requirements.first { $0.id == "gpu_toolkit" } }

    func testTheProbeReadsTheCardAndTheToolkitPrograms() {
        let read = facts(head + card + "tool=nvidia-ctk\ntool=nvidia-container-cli\n")
        XCTAssertEqual(read.nvidiaGpu, "NVIDIA GeForce RTX 5090")
        XCTAssertTrue(read.hasGpuToolkit)
        XCTAssertFalse(facts(head + card).hasGpuToolkit)
        XCTAssertTrue(RemoteProbe.script.contains("nvidia-smi -L"))
        XCTAssertTrue(RemoteProbe.script.contains("nvidia-ctk"))
    }

    func testTheRowExistsOnlyWhereACardWasFound() {
        XCTAssertNil(row(head), "no card, no row")
        XCTAssertNotNil(row(head + card))
        let mac = "os=Darwin\narch=arm64\nuser=m\nram_mb=16384\ndisk_free_gb=100\nsudo=password\nnvidia_gpu=Apple GPU\nport_9101=free\n"
        XCTAssertNil(row(mac), "a Mac never gets the row")
    }

    func testWithoutTheToolkitItIsACrossWithAFixAndAnOfferButDoesNotBlockAdding() throws {
        let missing = try XCTUnwrap(row(head + card))
        XCTAssertFalse(missing.ok)
        XCTAssertEqual(missing.label, "NVIDIA container toolkit (lets containers use the GPU)")
        XCTAssertEqual(missing.install, InstallOffer(part: "gpu_toolkit", needsPassword: true))
        XCTAssertTrue(try XCTUnwrap(missing.fix).contains("apt-get install -y nvidia-container-toolkit"))
        XCTAssertTrue(try XCTUnwrap(missing.fix).contains("docs.nvidia.com"))
        XCTAssertTrue(verify(head + card).canAdd, "the computer works without the toolkit")
    }

    func testWithTheToolkitItIsATick() throws {
        let present = try XCTUnwrap(row(head + card + "tool=nvidia-ctk\n"))
        XCTAssertTrue(present.ok)
        XCTAssertNil(present.install)
        XCTAssertNil(present.fix)
    }

    func testTheInstallIsOnlyOfferedOnAptWithSudo() throws {
        let otherManager = try XCTUnwrap(row(head.replacingOccurrences(of: "pkg=apt", with: "pkg=dnf") + card))
        XCTAssertNil(otherManager.install)
        XCTAssertTrue(try XCTUnwrap(otherManager.fix).contains("docs.nvidia.com"))
        XCTAssertNil(try XCTUnwrap(row(head.replacingOccurrences(of: "sudo=password", with: "sudo=none") + card)).install)
    }

    func testTheScriptIsNVIDIAsOfficialStepsInOrder() {
        let script = InstallMissingScripts.script(for: .gpuToolkit, user: "build", box: home)
        let steps = ["https://nvidia.github.io/libnvidia-container/gpgkey", "gpg --dearmor", "/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg",
                     "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list", "signed-by=", "/etc/apt/sources.list.d/nvidia-container-toolkit.list",
                     "aptget update", "aptget install nvidia-container-toolkit", "ms-done"]
        var from = script.startIndex
        for step in steps {
            let found = script.range(of: step, range: from..<script.endIndex)
            XCTAssertNotNil(found, step)
            from = found?.upperBound ?? from
        }
        XCTAssertFalse(script.contains("incus admin"), "nothing about Incus is touched")
    }
}
