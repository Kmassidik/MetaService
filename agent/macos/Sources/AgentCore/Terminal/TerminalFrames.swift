import Foundation

/// The size of the terminal window, in characters.
public struct TerminalSize: Equatable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }

    /// What a console starts with until the browser sends its real size.
    public static let initial = TerminalSize(cols: 80, rows: 24)
}

/// Why the helper closes a console socket: a WebSocket close code and a short plain reason. docs/console-contract.md.
public struct ConsoleClose: Equatable, Sendable {
    public let code: UInt16
    public let reason: String

    public static let normalCode: UInt16 = 1000
    public static let policyCode: UInt16 = 1008

    public static let vmStopped = ConsoleClose(code: normalCode, reason: "the VM stopped")
    public static let vmDeleted = ConsoleClose(code: normalCode, reason: "the VM was deleted")
    public static let shellEnded = ConsoleClose(code: normalCode, reason: "the shell ended")
    public static let badFrame = ConsoleClose(code: policyCode, reason: "that message was not allowed")
    public static let alreadyOpen = ConsoleClose(code: policyCode, reason: "this VM already has a console")
    public static let couldNotStart = ConsoleClose(code: policyCode, reason: "the shell could not start")
}

/// What one message from the browser means.
public enum ConsoleInput: Equatable, Sendable {
    case keys([UInt8])
    case resize(TerminalSize)
    /// Not allowed: the console is closed with 1008.
    case refused
}

/// The rules for what the browser may send. Pure: no sockets, no processes.
public enum TerminalFrames {
    /// A binary frame (keystrokes, paste) may hold at most this many bytes.
    public static let maxInputBytes = 65536
    public static let colsRange = 1...500
    public static let rowsRange = 1...300
    /// A resize message is tiny; anything longer than this is not one.
    static let maxResizeBytes = 64

    /// True when a binary frame is allowed through to the shell.
    public static func acceptsInput(byteCount: Int) -> Bool {
        byteCount <= maxInputBytes
    }

    public static func input(binary bytes: [UInt8]) -> ConsoleInput {
        acceptsInput(byteCount: bytes.count) ? .keys(bytes) : .refused
    }

    public static func input(text: String) -> ConsoleInput {
        parseResize(text).map(ConsoleInput.resize) ?? .refused
    }

    /// `{"resize":[cols,rows]}` with both numbers inside their bounds, or nil for anything else (extra keys, floats, strings, out of range).
    public static func parseResize(_ text: String) -> TerminalSize? {
        guard text.utf8.count <= maxResizeBytes, let data = text.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object.count == 1 else { return nil }
        guard let pair = object["resize"] as? [Any], pair.count == 2 else { return nil }
        guard let cols = wholeNumber(pair[0]), let rows = wholeNumber(pair[1]) else { return nil }
        guard colsRange.contains(cols), rowsRange.contains(rows) else { return nil }
        return TerminalSize(cols: cols, rows: rows)
    }

    /// JSON numbers only, whole ones only: `80` yes; `80.5`, `"80"` and `true` no.
    private static func wholeNumber(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        guard number.doubleValue == number.doubleValue.rounded(), abs(number.doubleValue) < 1e6 else { return nil }
        return number.intValue
    }
}
