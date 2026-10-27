import Darwin
import Foundation
import AgentCore

/// The last good storage map survives helper restarts. Cache writes replace the file atomically and stay owner-only.
struct DarwinStorageCache: Sendable {
    private static let maximumAge: TimeInterval = 24 * 60 * 60

    let path: String

    func load() -> StorageMap? {
        guard let modified = modificationDate(), Date().timeIntervalSince(modified) <= Self.maximumAge else { return nil }
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(StorageMap.self, from: data)
    }

    private func modificationDate() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date
    }

    func save(_ map: StorageMap) throws {
        let data = try JSONEncoder().encode(map)
        let temporary = path + ".tmp-" + UUID().uuidString
        guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw StorageScanFailure("the storage map could not be written")
        }
        let result = rename(temporary, path)
        guard result == 0 else {
            try? FileManager.default.removeItem(atPath: temporary)
            throw posixFailure("the storage map could not be replaced", code: result)
        }
    }
}
