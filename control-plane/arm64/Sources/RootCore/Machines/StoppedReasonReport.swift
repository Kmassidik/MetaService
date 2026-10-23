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
    static let keys: Set<String> = ["exit_code", "log_tail", "code", "message", "used_gb", "limit_gb"]
    /// The watchdog's code for a container that stayed over its GPU memory limit, and the numbers' range (a card has far less than this).
    static let codePattern = #/^[a-z0-9_]{1,64}$/#
    static let maxMessageBytes = 300
    static let gigabytes = 0.0...1_000_000.0

    public let exitCode: Int?
    public let logTail: String
    /// Optional, from the helper's watchdog: a short code, plain words, and for a GPU memory stop the memory used and the limit in GB.
    public let code: String?
    public let message: String?
    public let usedGb: Double?
    public let limitGb: Double?

    public init(exitCode: Int?, logTail: String, code: String? = nil, message: String? = nil, usedGb: Double? = nil, limitGb: Double? = nil) {
        self.exitCode = exitCode
        self.logTail = logTail
        self.code = code
        self.message = message
        self.usedGb = usedGb
        self.limitGb = limitGb
    }

    /// Every field is optional: the macOS helper sends `exit_code` and `log_tail`, the watchdog of the Linux helper only `code`, `message`, `used_gb` and `limit_gb`.
    init(_ object: StrictObject) throws {
        exitCode = object.has("exit_code") ? try object.int("exit_code", range: Self.exitCodes) : nil
        let rawTail = object.has("log_tail") ? try object.string("log_tail", maxLength: Self.maxReceivedCharacters) : ""
        logTail = UntrustedText.tail(rawTail, lines: Self.maxLines, maxBytes: Self.maxBytes)
        code = object.has("code") ? try object.string("code", pattern: Self.codePattern, maxLength: 64, minLength: 1) : nil
        message = try object.optionalString("message", maxLength: Self.maxReceivedCharacters).map { UntrustedText.tail($0, lines: Self.maxLines, maxBytes: Self.maxMessageBytes) }
        usedGb = object.has("used_gb") ? try object.double("used_gb", range: Self.gigabytes) : nil
        limitGb = object.has("limit_gb") ? try object.double("limit_gb", range: Self.gigabytes) : nil
    }

    enum CodingKeys: String, CodingKey { case exitCode, logTail, code, message, usedGb, limitGb }

    /// A missing value is sent as null, so the shape never changes.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(exitCode, forKey: .exitCode)
        try box.encode(logTail, forKey: .logTail)
        try box.encode(code, forKey: .code)
        try box.encode(message, forKey: .message)
        try box.encode(usedGb, forKey: .usedGb)
        try box.encode(limitGb, forKey: .limitGb)
    }

    /// Saved reasons from before the watchdog have only the first two.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(exitCode: try box.decodeIfPresent(Int.self, forKey: .exitCode), logTail: try box.decode(String.self, forKey: .logTail),
                  code: try box.decodeIfPresent(String.self, forKey: .code), message: try box.decodeIfPresent(String.self, forKey: .message),
                  usedGb: try box.decodeIfPresent(Double.self, forKey: .usedGb), limitGb: try box.decodeIfPresent(Double.self, forKey: .limitGb))
    }
}
