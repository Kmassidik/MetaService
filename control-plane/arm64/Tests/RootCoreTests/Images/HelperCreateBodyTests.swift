import XCTest
@testable import RootCore

final class HelperCreateBodyTests: XCTestCase {
    private func request(_ extra: [String: Any] = [:]) throws -> CreateWorkloadOperatorRequest {
        let base: [String: Any] = ["name": "demo", "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 20]
        return try CreateWorkloadOperatorRequest(body: JSONSerialization.data(withJSONObject: base.merging(extra) { $1 }))
    }

    private let ready = ImageEntry(id: "openclaw", title: "OpenClaw", description: "x", state: .ready, reason: nil, pinnedVersion: "1.0.0", sha256: String(repeating: "a", count: 64))

    func testABlankRequestIsTodaysBodyExactly() throws {
        let body = HelperCreateBody.make(commandId: "rc-1", request: try request(), machineDefaultImage: nil)
        XCTAssertEqual(Set(body.keys), ["command_id", "name", "kind", "cpu", "ram_mb", "disk_gb", "gpu_mode"])
        let named = HelperCreateBody.make(commandId: "rc-1", request: try request(["bundle": "blank"]), machineDefaultImage: nil)
        XCTAssertEqual(Set(named.keys), Set(body.keys))
    }

    func testTheImageIsOnlyEverTheMachinesOwnSavedDefault() throws {
        let body = HelperCreateBody.make(commandId: "rc-1", request: try request(), machineDefaultImage: "images:ubuntu/24.04")
        XCTAssertEqual(body["image"] as? String, "images:ubuntu/24.04")
    }

    func testABrowserSuppliedImageIsRefusedBeforeItCanReachAHelper() {
        for image in ["ubuntu:24.04", "docker.io/library/ubuntu:24.04", "--privileged", ""] {
            XCTAssertThrowsError(try request(["image": image]), image)
        }
    }

    func testAReadyBundleReachesTheHelperByItsCatalogId() throws {
        let body = HelperCreateBody.make(commandId: "rc-1", request: try request(["bundle": "openclaw"]), machineDefaultImage: nil, catalog: [ready])
        XCTAssertEqual(body["bundle"] as? String, "openclaw")
    }
}
