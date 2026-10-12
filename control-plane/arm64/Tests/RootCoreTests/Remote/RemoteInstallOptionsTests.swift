import XCTest
@testable import RootCore

final class RemoteInstallOptionsTests: XCTestCase {
    private func options(_ change: (inout RemoteInstallOptions) -> Void = { _ in }) -> RemoteInstallOptions {
        var value = RemoteInstallOptions.defaults(name: "office-mini", home: "/Users/kurnia", engine: "apple", rootURL: "http://192.168.100.40:9102")
        change(&value)
        return value
    }

    func testTheDefaultsPutTheBoxAndTheKeyInTheUsersHome() throws {
        let value = try options().validated()
        XCTAssertEqual(value.box, "/Users/kurnia/metaservice-box")
        XCTAssertEqual(value.sshDirectory, "/Users/kurnia/.ssh")
        XCTAssertEqual([value.agentPort, value.chatPort], [9101, 9200])
        XCTAssertEqual(value.level, .folder)
        XCTAssertTrue(value.installKey)
        XCTAssertFalse(value.installVmTool, "the VM tool is only added when ticked")
    }

    func testOnlyPlainAbsolutePathsPass() {
        for good in ["/Users/kurnia/metaservice-box", "/home/build/a.b/c_d", "/opt/x+y@z"] { XCTAssertTrue(RemoteInstallOptions.isPlainPath(good), good) }
        for bad in ["relative/path", "", "/", "/a/../b", "/a/./b", "/a//b", "/a b", "/a'b", "/a;b", "/a$b", "/a`b", "/a\nb", "~/x", "/" + String(repeating: "a", count: 201)] {
            XCTAssertFalse(RemoteInstallOptions.isPlainPath(bad), bad)
        }
        XCTAssertThrowsError(try options { $0.box = "/a b" }.validated())
        XCTAssertThrowsError(try options { $0.sshDirectory = "/a;b" }.validated())
    }

    func testTheNamePortAndEngineAreChecked() {
        XCTAssertThrowsError(try options { $0.name = "Bad Name" }.validated())
        XCTAssertThrowsError(try options { $0.name = "a/b" }.validated())
        for port in [0, 80, 1023, 65001] { XCTAssertThrowsError(try options { $0.agentPort = port }.validated(), String(port)) }
        XCTAssertEqual(try options { $0.agentPort = 9111 }.validated().chatPort, 9210)
        XCTAssertThrowsError(try options { $0.engine = "docker" }.validated())
        XCTAssertNoThrow(try options { $0.engine = "simulated" }.validated())
    }

    func testAUserOfItsOwnIsNotAvailableYet() {
        XCTAssertThrowsError(try options { $0.level = .dedicatedUser }.validated())
    }
}
