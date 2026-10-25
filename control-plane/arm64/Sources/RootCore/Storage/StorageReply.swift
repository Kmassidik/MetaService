import Foundation

/// The envelope the panel reads from `GET /api/machines/{id}/storage` and `POST .../storage/scan` (contract `MachineStorageReply`). Both keys are always written; storage is null unless the helper answered well.
public struct StorageReply: Encodable, Equatable, Sendable {
    public let state: String
    public let storage: Storage?

    /// online with the helper's checked answer, old_helper for a helper without the route, offline for a machine that is offline or did not answer well.
    public static func make(_ outcome: ReadingOutcome<Storage>) -> StorageReply {
        switch outcome {
        case .fresh(let storage): return StorageReply(state: "online", storage: storage)
        case .oldHelper: return StorageReply(state: "old_helper", storage: nil)
        case .unreachable: return StorageReply(state: "offline", storage: nil)
        }
    }

    private enum CodingKeys: String, CodingKey { case state, storage }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(state, forKey: .state)
        try box.encode(storage, forKey: .storage)
    }
}
