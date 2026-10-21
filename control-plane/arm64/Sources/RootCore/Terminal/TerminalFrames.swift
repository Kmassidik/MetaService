import Foundation

/// Why a console ended, in the contract's words: the WebSocket close code and a short plain reason for the person.
public struct CloseReason: Equatable, Sendable {
    public static let normalCode: UInt16 = 1000
    public static let policyCode: UInt16 = 1008
    public static let internalCode: UInt16 = 1011

    public let code: UInt16
    public let text: String

    public init(code: UInt16, text: String) {
        self.code = code
        self.text = text
    }

    public static let shellEnded = CloseReason(code: normalCode, text: "the shell ended")
    public static let idle = CloseReason(code: normalCode, text: "idle for 15 minutes")
    public static let tooLong = CloseReason(code: normalCode, text: "the console ran for 8 hours")
    public static let browserLeft = CloseReason(code: normalCode, text: "the console was closed")
    public static let vmStopped = CloseReason(code: normalCode, text: "the VM stopped")
    public static let vmDeleted = CloseReason(code: normalCode, text: "the VM was deleted")
    public static let machineRemoved = CloseReason(code: normalCode, text: "the machine was removed")
    public static let machineOffline = CloseReason(code: internalCode, text: "the machine is offline")
    public static let vmUnavailable = CloseReason(code: internalCode, text: "the VM is not available")
    public static let badFrame = CloseReason(code: policyCode, text: "that message is not allowed")
}

/// The rules for what the browser may send. The parent applies them to the size and shape of a frame and never reads keystrokes.
public enum TerminalFrames {
    public static let maxInputBytes = 65_536
    public static let maxTextBytes = 64
    public static let columns = 1...500
    public static let rows = 1...300

    /// A binary frame (keystrokes, paste) is allowed up to the limit.
    public static func checkInput(byteCount: Int) -> CloseReason? {
        byteCount <= maxInputBytes ? nil : .badFrame
    }

    /// A text frame must be exactly `{"resize":[cols,rows]}` with both numbers in range.
    public static func checkResize(text: String) -> CloseReason? {
        guard text.utf8.count <= maxTextBytes,
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              object.count == 1,
              let size = object["resize"] as? [Int],
              size.count == 2,
              columns.contains(size[0]), rows.contains(size[1]) else { return .badFrame }
        return nil
    }
}
