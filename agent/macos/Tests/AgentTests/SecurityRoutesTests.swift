import XCTest
import Hummingbird
import HummingbirdTesting
import AgentCore
@testable import Agent

/// The security route behind the same middleware stack as the real Agent, over a real local socket.
final class SecurityRoutesTests: XCTestCase {
    private let token = "t0ken-for-tests-only"
    private let lockout = 3

    private struct NoFiles: SshdConfigFiles, MacFiles {
        func read(_ path: String) -> String? { nil }
        func read(_ path: String) -> Data? { nil }
        func list(_ directory: String) -> [String]? { nil }
        func expand(_ pattern: String) -> [String] { [] }
    }

    private func application() -> some ApplicationProtocol {
        let reader = SecurityEventsReader(readLog: { _, _, _ in "" })
        let files = NoFiles()
        let service = SecurityService(reader: reader, sshdConfig: SshdConfigResolver(files: files), files: files, homeDirectory: "/nonexistent",
                                      run: { _, _ in throw CocoaError(.fileNoSuchFile) }, pending: PendingUpdates(run: { _, _, _ in throw CocoaError(.fileNoSuchFile) }))
        let router = Router(context: AgentContext.self)
        router.add(middleware: SecurityHeadersMiddleware())
        router.add(middleware: ErrorMiddleware())
        router.add(middleware: TokenMiddleware(token: token, badLimit: lockout))
        SecurityRoutes(service: service).register(on: router)
        return Application(router: router)
    }

    private var good: HTTPFields { [.authorization: "Bearer \(token)"] }

    func testAnAnswerHasTheContractShape() async throws {
        try await application().test(.live) { client in
            try await client.execute(uri: "/v1/security/events?limit=10", method: .get, headers: good) { response in
                XCTAssertEqual(response.status, .ok)
                let json = try JSONSerialization.jsonObject(with: response.body) as! [String: Any]
                XCTAssertEqual(Set(json.keys), ["cursor", "reset", "events", "baseline"])
                XCTAssertTrue((json["cursor"] as! String).hasPrefix("m1."))
                XCTAssertEqual(json["reset"] as? Bool, false)
                let baseline = json["baseline"] as! [String: Any]
                XCTAssertEqual(baseline["ban_tool"] as? String, "not_available")
                XCTAssertEqual(baseline["firewall"] as? NSNull, NSNull())
            }
        }
    }

    func testAGarbledCursorIsAResetNotAnError() async throws {
        try await application().test(.live) { client in
            try await client.execute(uri: "/v1/security/events?after=%3Cscript%3E", method: .get, headers: good) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual((try JSONSerialization.jsonObject(with: response.body) as! [String: Any])["reset"] as? Bool, true)
            }
        }
    }

    func testALimitOutsideOneToTwoThousandIsInvalidInput() async throws {
        try await application().test(.live) { client in
            for limit in ["0", "2001", "abc", "-5"] {
                try await client.execute(uri: "/v1/security/events?limit=\(limit)", method: .get, headers: good) { response in
                    XCTAssertEqual(response.status, .badRequest, limit)
                    let error = (try JSONSerialization.jsonObject(with: response.body) as! [String: Any])["error"] as! [String: Any]
                    XCTAssertEqual(error["code"] as? String, "invalid_input")
                }
            }
        }
    }

    func testNoTokenOrAWrongTokenIs401AndTooManyLockTheAddressOut() async throws {
        try await application().test(.live) { client in
            try await client.execute(uri: "/v1/security/events", method: .get) { XCTAssertEqual($0.status, .unauthorized) }
            try await client.execute(uri: "/v1/security/events", method: .get, headers: [.authorization: "Bearer wrong"]) { XCTAssertEqual($0.status, .unauthorized) }
            try await client.execute(uri: "/v1/security/events", method: .get, headers: [.authorization: "Bearer wrong"]) { XCTAssertEqual($0.status, .unauthorized) }
            try await client.execute(uri: "/v1/security/events", method: .get, headers: good) { response in
                XCTAssertEqual(response.status, .tooManyRequests, "after three wrong tokens even the right one is refused for a minute")
            }
        }
    }
}
