import XCTest
@testable import RootCore

final class SshArgumentsTests: XCTestCase {
    private let target = try! RemoteTarget(host: "192.168.100.40", port: 2222, user: "kurnia")

    func testAPasswordLoginHasNoPasswordInItAndAsksForOnePrompt() {
        let arguments = SshArguments.login(target: target, auth: .password, knownHosts: "/state/ssh/known_hosts", command: ["sh", "-s"])
        XCTAssertTrue(arguments.contains("NumberOfPasswordPrompts=1"))
        XCTAssertTrue(arguments.contains("PubkeyAuthentication=no"))
        XCTAssertFalse(arguments.contains { $0.lowercased().contains("password=") || $0.lowercased().contains("sshpass") })
        XCTAssertEqual(Array(arguments.suffix(3)), ["kurnia@192.168.100.40", "sh", "-s"])
    }

    func testTheDestinationComesAfterTwoDashesSoItCanNeverBeAnOption() {
        let arguments = SshArguments.login(target: target, auth: .password, knownHosts: "/k", command: ["sh", "-s"])
        let dashes = arguments.firstIndex(of: "--")!
        XCTAssertEqual(arguments[dashes + 1], "kurnia@192.168.100.40")
        XCTAssertEqual(arguments.filter { $0 == "--" }.count, 1)
    }

    func testAKeyLoginUsesOnlyThatKeyAndNoPassword() {
        let arguments = SshArguments.login(target: target, auth: .key(path: "/state/ssh/parent"), knownHosts: "/k", command: ["true"])
        XCTAssertTrue(arguments.contains("IdentitiesOnly=yes"))
        XCTAssertTrue(arguments.contains("BatchMode=yes"))
        XCTAssertTrue(arguments.contains("PasswordAuthentication=no"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "-i")! + 1], "/state/ssh/parent")
    }

    func testEveryLoginPinsTheHostKeyAndSwitchesOffForwardingAndSharing() {
        for auth in [SshAuth.password, .key(path: "/k")] {
            let arguments = SshArguments.login(target: target, auth: auth, knownHosts: "/state/known", command: ["true"])
            for required in ["StrictHostKeyChecking=yes", "UserKnownHostsFile=/state/known", "GlobalKnownHostsFile=/dev/null", "ForwardAgent=no", "ForwardX11=no", "ControlMaster=no", "ConnectTimeout=10"] {
                XCTAssertTrue(arguments.contains(required), required)
            }
            XCTAssertEqual(arguments[arguments.firstIndex(of: "-p")! + 1], "2222")
        }
    }

    func testTheUsersOwnSshConfigIsIgnored() {
        let arguments = SshArguments.login(target: target, auth: .password, knownHosts: "/k", command: ["true"])
        XCTAssertEqual(Array(arguments.prefix(2)), ["-F", "/dev/null"])
    }

    func testTheWayBackToTheParentIsOneLoopbackPortOnTheOtherComputerAndNothingElse() {
        let login = SshArguments.login(target: target, auth: .password, knownHosts: "/k", command: ["sh", "-s"], reversePort: 9102)
        XCTAssertEqual(login[login.firstIndex(of: "-R")! + 1], "127.0.0.1:9102:127.0.0.1:9102")
        XCTAssertTrue(login.contains("ExitOnForwardFailure=yes"), "a forward that cannot be made must fail the login, not be skipped")
        XCTAssertEqual(login.filter { $0 == "-R" }.count, 1)
        XCTAssertFalse(SshArguments.login(target: target, auth: .password, knownHosts: "/k", command: ["true"]).contains("-R"))
        let tunnel = SshArguments.tunnel(target: target, keyPath: "/k", knownHosts: "/kh", localPort: 54001, remotePort: 9101, reversePort: 9102)
        XCTAssertEqual(tunnel[tunnel.firstIndex(of: "-R")! + 1], "127.0.0.1:9102:127.0.0.1:9102")
        XCTAssertEqual(tunnel.last, "kurnia@192.168.100.40")
    }

    func testATunnelForwardsOneLocalLoopbackPortToTheAgentsLoopbackPort() {
        let arguments = SshArguments.tunnel(target: target, keyPath: "/k", knownHosts: "/kh", localPort: 54001, remotePort: 9101)
        XCTAssertEqual(arguments[arguments.firstIndex(of: "-L")! + 1], "127.0.0.1:54001:127.0.0.1:9101")
        XCTAssertTrue(arguments.contains("-N"))
        XCTAssertTrue(arguments.contains("ExitOnForwardFailure=yes"))
        XCTAssertEqual(arguments.last, "kurnia@192.168.100.40")
        XCTAssertFalse(arguments.contains("-R"), "no reverse forward in v1")
    }
}
