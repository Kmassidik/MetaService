import Foundation

/// One line of a helper's answer to `GET /v1/images`: which image it has prepared.
public struct HelperImage: Equatable {
    public let id: String
    public let ready: Bool

    static let keys: Set<String> = ["id", "ready", "built_at"]
    static let maxImages = 16
    static let longestBuiltAt = 64

    public init(id: String, ready: Bool) {
        self.id = id
        self.ready = ready
    }

    /// Reads a helper's JSON answer. Nil when it is not exactly the contract's shape.
    public static func parse(_ json: [String: Any]?) -> [HelperImage]? {
        guard let json, Set(json.keys) == ["images"], let rows = json["images"] as? [[String: Any]], rows.count <= maxImages else { return nil }
        let images = rows.compactMap(image)
        guard images.count == rows.count, Set(images.map(\.id)).count == images.count else { return nil }
        return images
    }

    private static func image(_ row: [String: Any]) -> HelperImage? {
        guard Set(row.keys) == keys, let id = row["id"] as? String, id.wholeMatch(of: ImageCatalog.pattern) != nil, let ready = row["ready"] as? Bool, builtAtIsValid(row["built_at"]) else { return nil }
        return HelperImage(id: id, ready: ready)
    }

    private static func builtAtIsValid(_ value: Any?) -> Bool {
        if value is NSNull { return true }
        guard let text = value as? String else { return false }
        return text.count <= longestBuiltAt
    }
}

/// What the parent learned from a machine's helper about its images.
public enum HelperImagesAnswer: Equatable {
    case answered([HelperImage])
    /// The helper has no images route (404): it only knows the stock image.
    case oldHelper
    /// The machine is offline or gave an answer that could not be read.
    case unreachable

    var key: String {
        switch self {
        case .answered: return "answered"
        case .oldHelper: return "old_helper"
        case .unreachable: return "unreachable"
        }
    }

    func isReady(_ id: String) -> Bool {
        guard case .answered(let images) = self else { return false }
        return images.first { $0.id == id }?.ready ?? false
    }
}

/// A catalog entry as one machine sees it.
public struct MachineImage: Encodable, Equatable {
    public let id: String
    public let title: String
    public let description: String
    public let state: ImageState
    /// Prepared on this machine.
    public let ready: Bool
    /// Can be chosen for this machine right now: the catalog allows it and the machine has it.
    public let available: Bool
    public let reason: String?

    enum CodingKeys: String, CodingKey { case id, title, description, state, ready, available, reason }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(state, forKey: .state)
        try container.encode(ready, forKey: .ready)
        try container.encode(available, forKey: .available)
        try container.encode(reason, forKey: .reason)
    }
}

public struct MachineImagesReply: Encodable, Equatable {
    static let needsPreparing = "This machine has to prepare the image first"

    public let helper: String
    public let images: [MachineImage]

    /// The catalog joined with what the helper says it has. Blank is the stock image and is ready on every machine. Names the helper reports that are not in the catalog are dropped.
    public static func merge(_ answer: HelperImagesAnswer, catalog: [ImageEntry] = ImageCatalog.entries) -> MachineImagesReply {
        MachineImagesReply(helper: answer.key, images: catalog.map { image($0, answer) })
    }

    private static func image(_ entry: ImageEntry, _ answer: HelperImagesAnswer) -> MachineImage {
        let ready = entry.id == ImageCatalog.blankId || answer.isReady(entry.id)
        let available = entry.isSelectable && ready
        return MachineImage(id: entry.id, title: entry.title, description: entry.description, state: entry.state, ready: ready, available: available, reason: reason(entry, ready: ready))
    }

    private static func reason(_ entry: ImageEntry, ready: Bool) -> String? {
        guard entry.isSelectable else { return entry.reason }
        return ready ? nil : needsPreparing
    }
}
