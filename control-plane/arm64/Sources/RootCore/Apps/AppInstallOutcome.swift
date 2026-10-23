import Foundation

/// What the machine's helper said to "install this app in the VM", reduced to what the parent does next.
/// Where it lives: `RootCore/Apps`. Pure, so every answer shape the helper can give is tested.
public enum AppInstallOutcome: Equatable {
    /// The app is in the VM. `changed` is false when it was there already.
    case installed(version: String?, installerSha256: String?, changed: Bool)
    /// The installer ran and failed: the helper's plain reason and the last lines it printed.
    case failed(message: String, logTail: [String])
    /// The helper has no apps route (404) or does not know the body (400).
    case helperTooOld
    /// No usable answer (the machine did not answer, the VM is stopped, ...). The install is still wanted; the heartbeat tries again.
    case notDone

    public static let maxLogLines = 12
    public static let maxLogLineCharacters = 200
    static let maxMessageCharacters = 300
    static let maxVersionCharacters = 64
    static let installFailedCode = "app_install_failed"
    private static let okStatus = 200
    private static let badGatewayStatus = 502
    private static let missingRouteStatus = 404
    private static let invalidStatus = 400
    private static let sha256Length = 64
    private static let firstPrintable: UInt32 = 0x20
    private static let delete: UInt32 = 0x7f

    public static func read(status: Int?, json: [String: Any]?, expectedApp: String) -> AppInstallOutcome {
        switch status {
        case okStatus: return installed(json, expectedApp: expectedApp) ?? .notDone
        case badGatewayStatus: return failure(json) ?? .notDone
        case missingRouteStatus, invalidStatus: return .helperTooOld
        default: return .notDone
        }
    }

    private static func installed(_ json: [String: Any]?, expectedApp: String) -> AppInstallOutcome? {
        guard let json, json["app"] as? String == expectedApp, let changed = json["installed"] as? Bool else { return nil }
        let version = (json["version"] as? String).map { String(plainLine($0).prefix(maxVersionCharacters)) }
        let sha = (json["installer_sha256"] as? String).flatMap { isSha256($0) ? $0 : nil }
        return .installed(version: version.flatMap { $0.isEmpty ? nil : $0 }, installerSha256: sha, changed: changed)
    }

    private static func failure(_ json: [String: Any]?) -> AppInstallOutcome? {
        guard let error = json?["error"] as? [String: Any], error["code"] as? String == installFailedCode else { return nil }
        let lines = (error["log_tail"] as? [Any])?.compactMap { $0 as? String } ?? []
        return .failed(message: message(from: error["message"] as? String), logTail: cleanLog(lines))
    }

    /// The helper's words as one plain line: control characters removed, cut at a limit. Anything empty becomes a generic sentence.
    static func message(from helperText: String?) -> String {
        let line = plainLine(helperText ?? "")
        return line.isEmpty ? AppRecord.unclearFailureMessage : String(line.prefix(maxMessageCharacters))
    }

    /// At most the last lines the installer printed, each cut and stripped of control characters; empty lines are dropped. Shown as text only.
    public static func cleanLog(_ lines: [String]) -> [String] {
        let kept = lines.map { String(plainLine($0).prefix(maxLogLineCharacters)) }.filter { !$0.isEmpty }
        return Array(kept.suffix(maxLogLines))
    }

    private static func plainLine(_ text: String) -> String {
        let printable = text.unicodeScalars.filter { $0.value >= firstPrintable && $0.value != delete }
        return String(String.UnicodeScalarView(printable)).trimmingCharacters(in: .whitespaces)
    }

    private static func isSha256(_ text: String) -> Bool {
        text.count == sha256Length && text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
