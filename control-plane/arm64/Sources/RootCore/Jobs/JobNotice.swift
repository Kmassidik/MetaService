import Foundation

/// What a user is told when a job ends: plain words from a fixed list, plus the machine or VM name (cleaned and cut short).
public struct JobNotice: Equatable, Sendable {
    public let kind: String
    public let title: String
    public let detail: String

    public static let maxName = 40
    public static let maxTitle = 80
    public static let maxDetail = 200
    private static let fallbackLabel = "Job"
    private static let labels = ["create": "Create VM", "delete": "Delete VM", "start": "Start VM", "stop": "Stop VM", "bundle_install": "Install chat",
                                 "bundle_uninstall": "Remove chat", "restart": "Restart service"]

    public static func kind(forState state: String) -> String? {
        switch state {
        case JobState.succeeded: return "job_succeeded"
        case JobState.failed: return "job_failed"
        case JobState.timedOut: return "job_timed_out"
        case JobState.lostContact: return "job_lost_contact"
        default: return nil
        }
    }

    /// Nil for a state that is not final.
    public static func make(type: String, state: String, machine: String, workload: String?, minutes: Int) -> JobNotice? {
        guard let kind = kind(forState: state) else { return nil }
        let label = labels[type] ?? fallbackLabel
        let target = workload.map { "\(clean($0)) on \(clean(machine))" } ?? clean(machine)
        let title: String
        let detail: String
        switch state {
        case JobState.succeeded:
            title = "\(label) finished"
            detail = "\(label) for \(target) finished."
        case JobState.failed:
            title = "\(label) failed"
            detail = "\(label) for \(target) did not finish. Open the job to see why, then try again."
        case JobState.timedOut:
            title = "\(label) took too long"
            detail = "\(label) for \(target) ran longer than \(minutes) minutes. The machine may still be working: check it before trying again."
        default:
            title = "\(label): lost contact"
            detail = "The machine stopped answering during \(label) for \(target). It may still be working: check it before trying again."
        }
        return JobNotice(kind: kind, title: String(title.prefix(maxTitle)), detail: String(detail.prefix(maxDetail)))
    }

    /// Control characters out (they can hide text or break a line), trimmed, and cut to `maxName` characters.
    public static func clean(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) }
        let plain = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return String(plain.prefix(maxName))
    }
}
