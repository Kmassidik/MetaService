import Foundation

/// The states a job (one row of the commands table) can be in. The last four are final.
public enum JobState {
    public static let queued = "queued"
    public static let running = "running"
    public static let succeeded = "succeeded"
    public static let failed = "failed"
    public static let timedOut = "timed_out"
    public static let lostContact = "lost_contact"

    public static let finals: Set<String> = [succeeded, failed, timedOut, lostContact]
    public static func isFinal(_ state: String) -> Bool { finals.contains(state) }
}

/// The only words a job may show as its current step. The helper chooses one of them; any other text (an engine's output, say) is ignored, so a step is always safe to show.
public enum JobSteps {
    public static let checking = "Checking the machine"
    public static let stopping = "Stopping the machine"
    public static let backingUp = "Backing up (this can take several minutes for big disks)"
    public static let deleting = "Deleting"
    public static let creating = "Creating the machine"
    public static let done = "Done"

    public static let all: Set<String> = [checking, stopping, backingUp, deleting, creating, done]
    public static func isKnown(_ text: String) -> Bool { all.contains(text) }
}

/// How long each kind of job may run before it is closed as timed out. One table, so the numbers are easy to find and change.
public enum JobLimits {
    public static let deleteSeconds = 30 * 60
    public static let createSeconds = 20 * 60
    /// The helper update is one SSH session, not a row in the commands table, so it is not watched here; the number is kept in the table for the update call.
    public static let updateHelperSeconds = 5 * 60
    /// Jobs that have no entry here (start, stop, chat) keep the general give-up time of `OrderFollowing`.
    public static let table: [String: Int] = ["delete": deleteSeconds, "create": createSeconds, "helper_update": updateHelperSeconds]

    public static func seconds(forType type: String) -> Int {
        table[type] ?? OrderFollowing.giveUpAfterSeconds
    }
}

/// What to do with a job that is still unfinished, given how long it has run and how long its machine has been silent.
public enum JobVerdict: Equatable, Sendable {
    case keepWaiting
    case timedOut(reason: String)
    case lostContact(reason: String)
}

public enum JobWatch {
    /// A job past its limit is timed out, even if the machine is also silent: the limit is the stronger fact.
    public static func verdict(type: String, createdAt: Date, now: Date, silentPolls: Int, step: String?) -> JobVerdict {
        let limit = JobLimits.seconds(forType: type)
        if now.timeIntervalSince(createdAt) > TimeInterval(limit) { return .timedOut(reason: timedOutReason(limitSeconds: limit, step: step)) }
        if silentPolls >= OrderFollowing.lostContactAfterPolls { return .lostContact(reason: lostContactReason(step: step)) }
        return .keepWaiting
    }

    public static func timedOutReason(limitSeconds: Int, step: String?) -> String {
        let minutes = max(1, limitSeconds / 60)
        let place = step.map { " It was at: \($0)." } ?? ""
        return "It took longer than \(minutes) minutes, so Meta stopped waiting.\(place) The machine may still be working: check it before trying again."
    }

    public static func lostContactReason(step: String?) -> String {
        let place = step.map { " The last step it reported was: \($0)." } ?? ""
        return "The machine stopped answering.\(place) It may still be working: check it before trying again."
    }

    /// The reason for a job that the helper never knew (the Root stopped between writing the job and sending it).
    public static let neverReceivedReason = "The machine never received this job. Nothing was changed. Try again."
}
