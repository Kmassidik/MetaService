import Foundation
import MSCore

/// Which app to put on top of a VM. The raw value is what the request carries and what the script prints.
public enum AppKind: String, CaseIterable, Sendable {
    case openclaw
    case hermes

    /// The constant script for this app.
    public var script: String {
        switch self {
        case .openclaw: AppInstallScripts.openclaw
        case .hermes: AppInstallScripts.hermes
        }
    }
}

/// The body of `PUT /v1/workloads/{id}/app`: exactly one field, `app`, which is `openclaw` or `hermes`. It is only the choice between the two constant scripts.
public struct AppInstallRequest: Equatable {
    public let app: AppKind

    private static let field = "app"

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: [Self.field])
        let name = try object.choice(Self.field, among: Set(AppKind.allCases.map(\.rawValue)))
        guard let kind = AppKind(rawValue: name) else { throw InputError("\(Self.field) is not an allowed value") }
        app = kind
    }
}

/// The answer of `PUT /v1/workloads/{id}/app` when it worked. `version` and `installer_sha256` are `null`, never left out, when unknown.
public struct AppInstalled: Encodable, Equatable, Sendable {
    public let app: String
    /// False: the app was already there and nothing was changed.
    public let installed: Bool
    public let version: String?
    public let installerSha256: String?

    public init(app: String, installed: Bool, version: String?, installerSha256: String?) {
        self.app = app
        self.installed = installed
        self.version = version
        self.installerSha256 = installerSha256
    }

    private enum CodingKeys: String, CodingKey {
        case app, installed, version
        case installerSha256 = "installer_sha256"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(app, forKey: .app)
        try container.encode(installed, forKey: .installed)
        try container.encode(version, forKey: .version)
        try container.encode(installerSha256, forKey: .installerSha256)
    }
}

/// Why the app could not be put in the VM, in plain words, with the last lines the installer printed (the 502 `app_install_failed` answer).
public struct AppInstallFailure: Error, Equatable, Sendable {
    public static let errorCode = "app_install_failed"
    static let unfinishedMessage = "The installer did not finish. The VM may have stopped answering or the install took too long."
    static let unreadableMessage = "The VM did not report what happened to the installer."

    public let message: String
    public let logTail: [String]

    public init(message: String, logTail: [String]) {
        self.message = message
        self.logTail = logTail
    }
}

/// The failure codes the script prints. The raw value is the code; `message` is what the person reads.
public enum AppScriptFailure: String, Equatable, Sendable {
    case noPackageManager = "no_package_manager"
    case prerequisitesFailed = "prerequisites_failed"
    case downloadFailed = "download_failed"
    case installFailed = "install_failed"

    public var message: String {
        switch self {
        case .noPackageManager: "The VM has no package manager the helper knows (apt-get), so it cannot install the packages the installer needs."
        case .prerequisitesFailed: "The VM could not install the packages the installer needs. Check that the VM has internet access."
        case .downloadFailed: "The VM could not download the installer. Check that the VM has internet access."
        case .installFailed: "The installer ran but the app is not in the VM afterwards."
        }
    }
}

/// What the script printed when it finished its work.
public enum AppInstallReport: Equatable, Sendable {
    case done(AppInstalled)
    case failed(AppScriptFailure)
}

/// Reading what an installer script printed: the result lines after the last marker, and the last lines of the installer's own output for the error body.
public enum AppInstallOutput {
    /// The most lines of installer output an error answer carries, and the most characters in each.
    public static let logTailLines = 12
    public static let logTailLineCharacters = 200
    private static let maxVersionCharacters = 100
    private static let sha256Pattern = #/^[0-9a-fA-F]{64}$/#

    private static let appPrefix = "app="
    private static let installedPrefix = "installed="
    private static let versionPrefix = "version="
    private static let sha256Prefix = "sha256="
    private static let failurePrefix = "failure="

    /// Reads the result lines after the last marker. Nil when there is no marker, the app is not the one asked for, a line is missing, or a value is not one we know.
    public static func parse(_ output: String, app: AppKind) -> AppInstallReport? {
        guard let marker = lines(output).lastIndex(where: { $0.trimmingTrailingWhitespace() == AppInstallScripts.resultMarker }) else { return nil }
        let results = Array(lines(output)[(marker + 1)...])
        guard value(results, appPrefix) == app.rawValue else { return nil }
        if let code = value(results, failurePrefix) { return AppScriptFailure(rawValue: code).map(AppInstallReport.failed) }
        guard let installed = flag(value(results, installedPrefix)) else { return nil }
        let version = value(results, versionPrefix).flatMap { isPlainVersion($0) ? $0 : nil }
        let hash = value(results, sha256Prefix).flatMap { $0.wholeMatch(of: sha256Pattern) != nil ? $0 : nil }
        return .done(AppInstalled(app: app.rawValue, installed: installed, version: version, installerSha256: hash))
    }

    /// The last lines the installer printed (everything before the last marker, or all of it without one): control characters removed, each line cut, empty lines dropped.
    public static func logTail(_ output: String) -> [String] {
        let all = lines(output)
        let end = all.lastIndex { $0.trimmingTrailingWhitespace() == AppInstallScripts.resultMarker } ?? all.count
        let clean = all[..<end]
            .map { String(String.UnicodeScalarView($0.unicodeScalars.filter { !isControl($0) })).trimmingCharacters(in: .whitespaces) }
            .map { String($0.prefix(logTailLineCharacters)) }
            .filter { !$0.isEmpty }
        return Array(clean.suffix(logTailLines))
    }

    private static func lines(_ output: String) -> [String] {
        output.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }).map(String.init)
    }

    private static func value(_ results: [String], _ prefix: String) -> String? {
        results.last { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)).trimmingTrailingWhitespace() }
    }

    private static func flag(_ text: String?) -> Bool? {
        switch text {
        case "true": true
        case "false": false
        default: nil
        }
    }

    private static func isPlainVersion(_ text: String) -> Bool {
        !text.isEmpty && text.count <= maxVersionCharacters && !text.unicodeScalars.contains(where: isControl)
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        String(reversed().drop(while: { $0.isWhitespace }).reversed())
    }
}
