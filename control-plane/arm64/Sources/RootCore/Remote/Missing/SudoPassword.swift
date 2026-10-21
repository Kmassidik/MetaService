import Foundation

/// The sudo password of the person, for one install. It prints as `<hidden>` whatever is done with it, goes to the other computer only as the first line of an ssh standard input,
/// and is overwritten when the install is over. Swift cannot promise that no other copy of a string was ever made (the request body held the text before it got here), but this
/// type never keeps one: only these bytes.
public final class SudoPassword: @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let hiddenText = "<hidden>"
    private static let masked = "***"
    private let lock = NSLock()
    private var bytes: [UInt8]

    public init(_ text: String) { bytes = Array(text.utf8) }

    public var isEmpty: Bool { lock.withLock { bytes.isEmpty } }
    public var description: String { Self.hiddenText }
    public var debugDescription: String { Self.hiddenText }

    /// What sudo reads with `-S`: the password and a line end. Nothing at all for an empty password (the computer needs none).
    public func standardInput() -> Data {
        lock.withLock { bytes.isEmpty ? Data() : Data(bytes + [UInt8(ascii: "\n")]) }
    }

    /// `text` with every copy of the password blanked out, for anything that comes back from the other computer before it is kept or shown.
    public func redacted(_ text: String) -> String {
        let secret = lock.withLock { String(decoding: bytes, as: UTF8.self) }
        guard !secret.isEmpty else { return text }
        return text.replacingOccurrences(of: secret, with: Self.masked)
    }

    public func wipe() {
        lock.withLock {
            bytes.withUnsafeMutableBufferPointer { buffer in
                guard let start = buffer.baseAddress else { return }
                memset_s(start, buffer.count, 0, buffer.count)
            }
            bytes.removeAll()
        }
    }
}
