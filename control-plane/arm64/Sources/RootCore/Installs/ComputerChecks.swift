import Foundation

/// One thing a computer needs before MetaService can do its whole job, and whether it has it.
public struct Requirement: Encodable, Equatable {
    public let id: String
    public let label: String
    public let ok: Bool
    /// Whether the install can finish without it: false means the install itself cannot work.
    public let optional: Bool
    /// What was found, or what is missing and what that means, in plain words.
    public let detail: String
}

/// What a computer needs before MetaService can do its whole job.
public enum ComputerChecks {
    /// Room a first VM image and its disk need at the least.
    public static let minimumFreeDiskGb = 20
}
