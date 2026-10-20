import Foundation
import MSCore

public enum MouseButton: String, Equatable, Sendable {
    case left, right, middle
}

/// One thing the operator did at the screen. Positions are in ten-thousandths of the screen's width and height, so they do not depend on the size the viewer shows.
public enum ScreenInputEvent: Equatable, Sendable {
    case move(x: Int, y: Int)
    case button(MouseButton, down: Bool)
    case scroll(dx: Int, dy: Int)
    case key(code: Int, down: Bool)
}

/// The body of POST /v1/screen/input, read strictly: a bounded number of events with bounded values.
public struct ScreenInputRequest: Equatable, Sendable {
    public let events: [ScreenInputEvent]

    public static let maxEvents = 64
    public static let positionScale = 10_000
    public static let maxScroll = 50
    /// macOS virtual key codes run from 0 to 127.
    public static let maxKeyCode = 127

    public init(body: Data) throws {
        let root = try StrictObject(data: body, allowed: ["events"])
        let items = try root.objects("events", allowed: ["type", "x", "y", "button", "down", "dx", "dy", "code"], maxCount: Self.maxEvents)
        events = try items.map(Self.event)
    }

    private static func event(_ item: StrictObject) throws -> ScreenInputEvent {
        switch try item.choice("type", among: ["move", "button", "scroll", "key"]) {
        case "move":
            return .move(x: try item.int("x", range: 0...positionScale), y: try item.int("y", range: 0...positionScale))
        case "button":
            let name = try item.choice("button", among: ["left", "right", "middle"])
            return .button(MouseButton(rawValue: name)!, down: try item.bool("down"))
        case "scroll":
            return .scroll(dx: try item.int("dx", range: -maxScroll...maxScroll), dy: try item.int("dy", range: -maxScroll...maxScroll))
        default:
            return .key(code: try item.int("code", range: 0...maxKeyCode), down: try item.bool("down"))
        }
    }
}
