import Foundation
import MSCore

/// `metaservice-agent enroll`: trade a one-time enrollment token for this machine's permanent token, and save it (mode 600).
enum Enroller {
    static func run(root: String, name: String, tokenFile: String?, config: AgentConfig) async throws {
        guard Ids.isValid(name) else { throw ConfigError(description: "--name must use lowercase letters, numbers and dashes") }
        let base = try RootLink.validated(root)
        let token = try readToken(tokenFile)
        var request = URLRequest(url: base.appendingPathComponent("v1/agents/enroll"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["enrollment_token": token, "name": name])
        let (data, response) = try await RootLink.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let machineToken = reply["machine_token"] as? String else { throw ConfigError(description: "the Root refused the enrollment (wrong, used or expired token, or wrong address)") }
        try save(machineToken: machineToken, root: root, name: name, config: config)
        print("enrolled as \(name); token saved in \(config.stateDirectory)")
    }

    private static func readToken(_ file: String?) throws -> String {
        if let file {
            let text = try String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ConfigError(description: "the token file is empty") }
            return text
        }
        guard let text = ProcessInfo.processInfo.environment["MS_ENROLLMENT_TOKEN"], !text.isEmpty else {
            throw ConfigError(description: "give the enrollment token with --enrollment-token-file or the MS_ENROLLMENT_TOKEN variable (never as a plain argument)")
        }
        return text
    }

    private static func save(machineToken: String, root: String, name: String, config: AgentConfig) throws {
        try FileManager.default.createDirectory(atPath: config.stateDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try write(machineToken, to: config.tokenFile)
        let settings = try JSONSerialization.data(withJSONObject: ["root": root, "name": name])
        try write(String(decoding: settings, as: UTF8.self), to: config.settingsFile)
    }

    private static func write(_ text: String, to path: String) throws {
        FileManager.default.createFile(atPath: path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
    }
}

/// How the Agent talks to the Root: plain URLSession, no redirects, short timeouts.
enum RootLink {
    static let session: URLSession = {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 15
        options.httpCookieStorage = nil
        options.urlCache = nil
        return URLSession(configuration: options, delegate: NoRedirect(), delegateQueue: nil)
    }()

    static func validated(_ text: String) throws -> URL {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme), url.host != nil, url.user == nil, url.query == nil else {
            throw ConfigError(description: "--root must be an http(s) address such as http://192.168.100.40:9100")
        }
        return url
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
