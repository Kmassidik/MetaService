import Foundation

/// One thing a computer needs before MetaService can do its whole job, and whether it has it. There is no "maybe": it is there (ok) or it is not.
public struct Requirement: Encodable, Equatable {
    public let id: String
    public let label: String
    public let ok: Bool
    /// What was found, or what is missing and what that means, in plain words.
    public let detail: String
    /// What the person should do to fix it. Only set when `ok` is false.
    public let fix: String?
    /// Set when the parent can install what is missing itself (a button and a password field under the cross).
    public let install: InstallOffer?

    public init(id: String, label: String, ok: Bool, detail: String, fix: String? = nil, install: InstallOffer? = nil) {
        self.id = id
        self.label = label
        self.ok = ok
        self.detail = detail
        self.fix = ok ? nil : fix
        self.install = ok ? nil : install
    }
}

/// What a computer needs before MetaService can do its whole job.
public enum ComputerChecks {
    /// Room a first VM image and its disk need at the least.
    public static let minimumFreeDiskGb = 20
}
