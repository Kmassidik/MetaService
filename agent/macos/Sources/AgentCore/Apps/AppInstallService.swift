import Foundation

/// How an app install is run: ONE `container exec -i` of `/bin/bash -s` with the constant script on standard input.
/// Where it lives: macOS helper, `Sources/AgentCore/Apps/`. The Linux helper does the same through `incus exec` in `agent/linux/src/apps/`.
public enum AppInstallCall {
    /// The most an app install may take (the parent waits 25 minutes).
    public static let timeout: TimeInterval = 20 * 60
    static let shellPath = "/bin/bash"

    /// The `container exec` arguments (after the tool's own path). Nothing from a request is in them; `-i` keeps standard input open for the script.
    public static func arguments(id: String) -> [String] {
        ["exec", "-i", AppleContainer.name(for: id), shellPath, "-s"]
    }

    /// Reads what the script printed into the answer, or into the failure with plain words and the installer's last lines.
    public static func result(_ output: String, app: AppKind) throws -> AppInstalled {
        let tail = AppInstallOutput.logTail(output)
        switch AppInstallOutput.parse(output, app: app) {
        case .done(let installed): return installed
        case .failed(let failure): throw AppInstallFailure(message: failure.message, logTail: tail)
        case nil: throw AppInstallFailure(message: AppInstallFailure.unreadableMessage, logTail: tail)
        }
    }
}

extension AgentService {
    /// Puts OpenClaw or Hermes on top of one running VM (see `Engine.installApp`). An unknown VM is `notFound`, a stopped one `notRunning`;
    /// a run that breaks or takes too long, or whose report says it failed, is an `AppInstallFailure`.
    public func installApp(id: String, app: AppKind) async throws -> AppInstalled {
        let output: String
        do { output = try await engine.installApp(id: id, app: app) } catch EngineError.failed {
            throw AppInstallFailure(message: AppInstallFailure.unfinishedMessage, logTail: [])
        }
        return try AppInstallCall.result(output, app: app)
    }
}
