import Foundation

/// The apps that are installed inside a plain VM after it starts (OpenClaw, Hermes), as opposed to images the machine prepares beforehand.
/// Where it lives: `RootCore/Apps`. Pure rules only; the work is in `Root/Apps`.
public enum AppCatalog {
    public static let names: Set<String> = ["openclaw", "hermes"]
    /// Shown for an app the machine's helper cannot install yet, because it is an older build.
    public static let oldHelperReason = "Update the helper on this machine first"
    public static let oldHelperFailure = "This machine's helper is too old for apps. Press Update helper in its Environment tab."
    /// The helper gives an install 25 minutes at most, so the parent waits that long for the one call.
    public static let callSeconds: TimeInterval = 25 * 60

    public static func isApp(_ id: String) -> Bool { names.contains(id) }
}
