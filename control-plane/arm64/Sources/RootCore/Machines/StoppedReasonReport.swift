import Foundation
import MSCore

/// Why a VM stopped by itself, as its helper reports it (contract 1.3.0, optional field `stopped_reason`).
/// `logTail` is text from inside the VM: it is cleaned and capped again here and is never treated as anything but text.
public struct StoppedReasonReport: Equatable, Codable {
    public static let maxLines = 12
    public static let maxBytes = 2048
    /// What the parent reads at most. A helper that sends a little more than it should still gets its report kept, cut down.
    static let maxReceivedCharacters = 20_000
    static let exitCodes = -1000...1000
    static let keys: Set<String> = ["exit_code", "log_tail"]

    public let exitCode: Int?
    public let logTail: String

    public init(exitCode: Int?, logTail: String) {
        self.exitCode = exitCode
        self.logTail = logTail
    }

    init(_ object: StrictObject) throws {
        exitCode = object.has("exit_code") ? try object.int("exit_code", range: Self.exitCodes) : nil
        logTail = UntrustedText.tail(try object.string("log_tail", maxLength: Self.maxReceivedCharacters), lines: Self.maxLines, maxBytes: Self.maxBytes)
    }

    enum CodingKeys: String, CodingKey { case exitCode, logTail }

    /// A missing exit code is sent as null, so the shape never changes.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(exitCode, forKey: .exitCode)
        try box.encode(logTail, forKey: .logTail)
    }
}
