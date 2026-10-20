import Foundation

public enum InstallState: String, Encodable {
    case pending, running, done, failed
}

public struct InstallStep: Encodable, Equatable {
    public let id: String
    public let label: String
    public var state: InstallState
    public var detail: String?

    public init(id: String, label: String, state: InstallState = .pending, detail: String? = nil) {
        self.id = id
        self.label = label
        self.state = state
        self.detail = detail
    }
}
