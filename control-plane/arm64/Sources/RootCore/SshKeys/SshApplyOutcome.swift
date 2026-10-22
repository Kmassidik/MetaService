import Foundation

/// What the machine's helper said to "put these keys in the VM and set up its SSH server", reduced to what the Root does next.
/// Where it lives: `RootCore/SshKeys`. Pure, so every answer shape the helper can give is tested.
public enum SshApplyOutcome: Equatable {
    /// The keys are in the VM and its SSH server is up. `sshd` is what the helper reported, when it is one of the known words.
    case applied(sshd: String?)
    /// The keys are in the VM but the SSH server could not be set up; `message` is the helper's plain reason.
    case sshdFailed(message: String)
    /// The helper does not know the `install_sshd` field.
    case helperTooOld
    /// No usable answer (the machine did not answer, the VM is stopped, ...). The next heartbeat tries again.
    case notApplied

    static let knownSshdStates: Set<String> = ["running", "installed", "missing"]
    static let installFailedCode = "sshd_install_failed"
    private static let okStatus = 200
    private static let badGatewayStatus = 502
    private static let invalidStatus = 400

    public static func read(status: Int?, json: [String: Any]?, expectedKeys: Int) -> SshApplyOutcome {
        switch status {
        case Self.okStatus: return json?["applied"] as? Int == expectedKeys ? .applied(sshd: (json?["sshd"] as? String).flatMap { knownSshdStates.contains($0) ? $0 : nil }) : .notApplied
        case Self.badGatewayStatus: return installFailure(json) ?? .notApplied
        case Self.invalidStatus: return .helperTooOld
        default: return .notApplied
        }
    }

    private static func installFailure(_ json: [String: Any]?) -> SshApplyOutcome? {
        guard let error = json?["error"] as? [String: Any], error["code"] as? String == installFailedCode else { return nil }
        return .sshdFailed(message: SshdProgress.failureMessage(from: error["message"] as? String))
    }
}
