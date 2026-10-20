import Foundation

/// A screen that is not real: a 160 x 100 picture with a square where the pointer last was. It records the events it got, so tests can check them.
public actor SimulatedScreen: ScreenSource {
    public static let width = 160
    public static let height = 100
    private static let markerSize = 8

    private var pointer = (x: 0, y: 0)
    private var pressed = false
    private var received: [ScreenInputEvent] = []
    private let access: ScreenAccess

    public init(access: ScreenAccess = .ready) {
        self.access = access
    }

    public var events: [ScreenInputEvent] { received }

    public func status() async -> ScreenStatus {
        ScreenStatus(access: access, width: Self.width, height: Self.height, message: access == .ready ? nil : "Allow Screen Recording and Accessibility for the MetaService program.")
    }

    public func frame() async throws -> ScreenFrame {
        guard access == .ready else { throw ScreenError.notAllowed("The permission is missing on this computer.") }
        let (px, py, down) = (pointer.x * Self.width / ScreenInputRequest.positionScale, pointer.y * Self.height / ScreenInputRequest.positionScale, pressed)
        let png = PngImage.rgb(width: Self.width, height: Self.height) { column, row in
            let inMarker = abs(column - px) < Self.markerSize && abs(row - py) < Self.markerSize
            if inMarker { return down ? (255, 64, 64) : (255, 255, 255) }
            return (UInt8(30 + column), UInt8(40 + row), 90)
        }
        return ScreenFrame(contentType: "image/png", data: png)
    }

    public func send(_ events: [ScreenInputEvent]) async throws {
        guard access == .ready else { throw ScreenError.notAllowed("The permission is missing on this computer.") }
        for event in events {
            received.append(event)
            apply(event)
        }
    }

    private func apply(_ event: ScreenInputEvent) {
        switch event {
        case .move(let x, let y): pointer = (x, y)
        case .button(_, let down): pressed = down
        case .scroll, .key: break
        }
    }
}
