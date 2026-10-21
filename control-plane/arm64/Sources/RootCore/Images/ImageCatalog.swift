import Foundation

public enum ImageState: String, Encodable, Equatable, Sendable {
    /// Can be chosen when a VM is made.
    case ready
    /// Listed so people can see it is coming, but not selectable yet.
    case planned
}

/// One ready-made image the parent knows about. The panel only ever names an image by its `id`; the pinned version and checksum stay on the parent.
public struct ImageEntry: Equatable, Encodable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let state: ImageState
    /// Why it cannot be chosen yet, in plain words. Nil for a ready entry.
    public let reason: String?
    /// Filled in when an image is built from a pinned release. Empty for planned entries, and never sent to the panel.
    public let pinnedVersion: String?
    public let sha256: String?

    public var isSelectable: Bool { state == .ready }

    enum CodingKeys: String, CodingKey { case id, title, description, state, reason }

    public init(id: String, title: String, description: String, state: ImageState, reason: String?, pinnedVersion: String?, sha256: String?) {
        self.id = id
        self.title = title
        self.description = description
        self.state = state
        self.reason = reason
        self.pinnedVersion = pinnedVersion
        self.sha256 = sha256
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(state, forKey: .state)
        try container.encode(reason, forKey: .reason)
    }
}

public enum ImageChoiceError: Error, Equatable {
    /// The name is not in the catalog.
    case unknown
    /// The name is listed but cannot be chosen yet.
    case notAvailable(reason: String)
}

/// The images a VM can start from. The parent owns this list: the browser sends one of these ids and nothing else, and the parent decides what a helper is told.
public enum ImageCatalog {
    public static let blankId = "blank"
    static let pattern = #/^[a-z0-9][a-z0-9-]{0,31}$/#
    static let comingSoon = "Coming soon: needs the image to be prepared on the machine"
    static let waitingForPin = "Waiting for a pinned release and checksum"

    public static let entries: [ImageEntry] = [
        ImageEntry(id: blankId, title: "Blank (plain Ubuntu)", description: "Ubuntu 24.04 with the usual server tools. Nothing else.", state: .ready, reason: nil, pinnedVersion: nil, sha256: nil),
        ImageEntry(id: "openclaw", title: "OpenClaw", description: "Blank, plus the OpenClaw assistant already installed.", state: .planned, reason: comingSoon, pinnedVersion: nil, sha256: nil),
        ImageEntry(id: "hermes", title: "Hermes", description: "Blank, plus the Hermes assistant already installed.", state: .planned, reason: waitingForPin, pinnedVersion: nil, sha256: nil),
    ]

    public static func entry(id: String, in catalog: [ImageEntry] = entries) -> ImageEntry? {
        catalog.first { $0.id == id }
    }

    /// The entry a create request asks for: none given means Blank. Throws when the name is unknown or the entry cannot be chosen yet.
    public static func choose(_ id: String?, in catalog: [ImageEntry] = entries) throws -> ImageEntry {
        guard let id else { return try choose(blankId, in: catalog) }
        guard let found = entry(id: id, in: catalog) else { throw ImageChoiceError.unknown }
        guard found.isSelectable else { throw ImageChoiceError.notAvailable(reason: found.reason ?? comingSoon) }
        return found
    }

    /// What goes to a helper in the create command's `bundle` field. Blank sends nothing (that is today's request exactly, which every helper understands), and so does anything not ready.
    public static func helperBundle(for id: String, in catalog: [ImageEntry] = entries) -> String? {
        guard id != blankId, let found = entry(id: id, in: catalog), found.isSelectable else { return nil }
        return found.id
    }
}
