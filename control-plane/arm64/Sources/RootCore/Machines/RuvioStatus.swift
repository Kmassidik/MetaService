import Foundation

/// Where Ruvio (the chat) stands on one machine, from what the helper reports and what the parent has pinned.
public enum RuvioState: String, Encodable, Equatable {
    /// Nothing is pinned and nothing is installed, so it cannot be turned on.
    case unavailable
    case off
    case on
    /// Another version than the pinned one runs.
    case outdated
    case installing
    case removing
}

/// The chat commands the parent can have going on a machine.
public enum BundleCommandKind: String, Equatable {
    case install = "bundle_install"
    case uninstall = "bundle_uninstall"
}

public struct RuvioStatus: Encodable, Equatable {
    public let installed: String?
    public let pinned: String?
    public let state: RuvioState

    enum CodingKeys: String, CodingKey { case installed, pinned, state }

    /// Missing versions are sent as null, so the shape never changes.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(installed, forKey: .installed)
        try box.encode(pinned, forKey: .pinned)
        try box.encode(state, forKey: .state)
    }

    /// `going` is the chat command that has not finished yet, if any: it wins over what the machine last reported.
    public static func make(installed: String?, pinned: String?, going: BundleCommandKind?) -> RuvioStatus {
        RuvioStatus(installed: installed, pinned: pinned, state: state(installed: installed, pinned: pinned, going: going))
    }

    private static func state(installed: String?, pinned: String?, going: BundleCommandKind?) -> RuvioState {
        switch going {
        case .install?: return .installing
        case .uninstall?: return .removing
        case nil: break
        }
        guard let installed else { return pinned == nil ? .unavailable : .off }
        guard let pinned else { return .on }
        return installed == pinned ? .on : .outdated
    }
}
