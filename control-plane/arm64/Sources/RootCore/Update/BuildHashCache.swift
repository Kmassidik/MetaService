import CryptoKit
import Foundation

/// The build (SHA-256, lowercase hex) of the helper programs the parent can install. A program is read again only when its size or its modified time changed.
public final class BuildHashCache: @unchecked Sendable {
    private struct Entry {
        let size: UInt64
        let modified: Date
        let build: String
    }

    private static let pieceBytes = 1 << 20
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var computed = 0

    public init() {}

    /// How many files were really read. Only the tests look at this.
    var hashesComputed: Int { lock.withLock { computed } }

    /// The build of the file at `path`, or nil when it cannot be read as a file.
    public func build(ofFileAt path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path), attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value, let modified = attributes[.modificationDate] as? Date else { return nil }
        if let known = lock.withLock({ entries[path] }), known.size == size, known.modified == modified { return known.build }
        guard let build = Self.sha256(ofFileAt: path) else { return nil }
        lock.withLock {
            entries[path] = Entry(size: size, modified: modified, build: build)
            computed += 1
        }
        return build
    }

    static func sha256(ofFileAt path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        while let piece = try? handle.read(upToCount: pieceBytes), !piece.isEmpty { hash.update(data: piece) }
        return hex(hash.finalize())
    }

    static func sha256(of data: Data) -> String { hex(SHA256.hash(data: data)) }

    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
}
