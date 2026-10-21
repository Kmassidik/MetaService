import XCTest
@testable import RootCore

final class GpuCheckReplyTests: XCTestCase {
    private let good: [String: Any] = ["gpu_visible": true, "how": "nvidia-smi", "detail": "NVIDIA GeForce RTX 5090, 580.178.04, 32607 MiB", "note": "The GPU is visible inside, and nvidia-smi can talk to it."]

    private func parse(_ changes: [String: Any] = [:]) -> GpuCheckReply? { GpuCheckReply.parse(good.merging(changes) { $1 }) }

    func testAHelpersAnswerIsRead() {
        XCTAssertEqual(parse(), GpuCheckReply(gpuVisible: true, how: "nvidia-smi", detail: "NVIDIA GeForce RTX 5090, 580.178.04, 32607 MiB", note: "The GPU is visible inside, and nvidia-smi can talk to it."))
        XCTAssertEqual(parse(["how": "device nodes", "detail": ""])?.how, "device nodes")
        XCTAssertEqual(parse(["gpu_visible": false, "how": "none"])?.gpuVisible, false)
    }

    func testAnythingButTheContractsShapeIsRefused() {
        XCTAssertNil(GpuCheckReply.parse(nil))
        XCTAssertNil(parse(["how": "magic"]))
        XCTAssertNil(parse(["gpu_visible": "yes"]))
        XCTAssertNil(parse(["note": ""]))
        XCTAssertNil(parse(["note": 5]))
        XCTAssertNil(parse(["extra": 1]))
        var missing = good
        missing["detail"] = nil
        XCTAssertNil(GpuCheckReply.parse(missing))
    }

    func testHostileTextIsCutToShortPrintableText() {
        let reply = parse(["detail": "<script>x</script>\u{1b}[31m\u{7}ok\n" + String(repeating: "y", count: 5000), "note": String(repeating: "n", count: 900) + "\u{0}"])
        XCTAssertEqual(reply?.detail.count, GpuCheckReply.longestDetail)
        XCTAssertEqual(reply?.note.count, GpuCheckReply.longestNote)
        XCTAssertFalse(reply?.detail.contains("\u{1b}") ?? true)
        XCTAssertFalse(reply?.detail.contains("\u{7}") ?? true)
        XCTAssertTrue(reply?.detail.hasPrefix("<script>x</script>[31mok\n") ?? false, "the text itself is kept as text")
    }

    func testOnlyAContainerWithTheGpuCanHaveItInside() {
        XCTAssertTrue(GpuCheckReply.canHaveGpu(kind: "container", gpuMode: "container"))
        XCTAssertFalse(GpuCheckReply.canHaveGpu(kind: "container", gpuMode: "none"))
        XCTAssertFalse(GpuCheckReply.canHaveGpu(kind: "vm", gpuMode: "container"))
        XCTAssertFalse(GpuCheckReply.canHaveGpu(kind: "vm", gpuMode: "passthrough"))
        XCTAssertEqual(GpuCheckReply.notGiven.note, "No GPU was given to this one.")
        XCTAssertFalse(GpuCheckReply.notGiven.gpuVisible)
    }
}
