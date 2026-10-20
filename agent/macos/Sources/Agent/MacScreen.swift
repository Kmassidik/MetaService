import ApplicationServices
import AgentCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The real screen of this Mac. Needs two permissions that only the person at the Mac can give: Screen Recording (to see) and Accessibility (to click and type).
struct MacScreen: ScreenSource {
    private static let longestEdge = 1600
    private static let jpegQuality = 0.6
    private static let missing = "On this Mac, open System Settings > Privacy & Security and allow Screen Recording and Accessibility for the MetaService program."

    func status() async -> ScreenStatus {
        let display = CGMainDisplayID()
        let size = (width: Int(CGDisplayPixelsWide(display)), height: Int(CGDisplayPixelsHigh(display)))
        guard CGPreflightScreenCaptureAccess(), AXIsProcessTrusted() else { return ScreenStatus(access: .needsPermission, width: size.width, height: size.height, message: Self.missing) }
        return ScreenStatus(access: .ready, width: size.width, height: size.height)
    }

    func frame() async throws -> ScreenFrame {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenError.notAllowed(Self.missing) }
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else { throw ScreenError.notAllowed("The screen cannot be read right now.") }
        guard let data = Self.jpeg(image) else { throw ScreenError.notAllowed("The screen picture could not be made.") }
        return ScreenFrame(contentType: "image/jpeg", data: data)
    }

    func send(_ events: [ScreenInputEvent]) async throws {
        guard AXIsProcessTrusted() else { throw ScreenError.notAllowed(Self.missing) }
        let bounds = CGDisplayBounds(CGMainDisplayID())
        for event in events { Self.post(event, in: bounds) }
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let scale = min(1.0, Double(longestEdge) / Double(max(image.width, image.height)))
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality, kCGImageDestinationImageMaxPixelSize: Int(Double(max(image.width, image.height)) * scale)]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func post(_ event: ScreenInputEvent, in bounds: CGRect) {
        switch event {
        case .move(let x, let y):
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point(x, y, bounds), mouseButton: .left)?.post(tap: .cghidEventTap)
        case .button(let button, let down):
            let location = CGEvent(source: nil)?.location ?? bounds.origin
            let (type, which) = mouse(button, down: down)
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: which)?.post(tap: .cghidEventTap)
        case .scroll(let dx, let dy):
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)?.post(tap: .cghidEventTap)
        case .key(let code, let down):
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)?.post(tap: .cghidEventTap)
        }
    }

    private static func point(_ x: Int, _ y: Int, _ bounds: CGRect) -> CGPoint {
        let scale = Double(ScreenInputRequest.positionScale)
        return CGPoint(x: bounds.origin.x + bounds.width * Double(x) / scale, y: bounds.origin.y + bounds.height * Double(y) / scale)
    }

    private static func mouse(_ button: MouseButton, down: Bool) -> (CGEventType, CGMouseButton) {
        switch button {
        case .left: return (down ? .leftMouseDown : .leftMouseUp, .left)
        case .right: return (down ? .rightMouseDown : .rightMouseUp, .right)
        case .middle: return (down ? .otherMouseDown : .otherMouseUp, .center)
        }
    }
}
