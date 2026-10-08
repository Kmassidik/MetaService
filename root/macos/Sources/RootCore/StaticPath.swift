import Foundation

/// Decides which files the Root may serve for the panel UI. Anything odd is refused, never "fixed".
public enum StaticPath {
    private static let allowed = try! Regex("^[A-Za-z0-9._/-]{1,200}$")
    public static let indexFile = "index.html"

    /// The file path inside the UI folder for a request path, or nil if it must be refused.
    public static func clean(_ requestPath: String) -> String? {
        guard requestPath.wholeMatch(of: allowed) != nil, requestPath.hasPrefix("/") else { return nil }
        let relative = String(requestPath.dropFirst())
        guard !relative.isEmpty else { return indexFile }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.isEmpty || $0.hasPrefix(".") }) else { return nil }
        return relative
    }

    public static func isHashedAsset(_ file: String) -> Bool {
        file.hasPrefix("assets/")
    }

    public static func contentType(for file: String) -> String? {
        switch (file as NSString).pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "ico": return "image/x-icon"
        case "json", "webmanifest": return "application/json"
        case "woff2": return "font/woff2"
        default: return nil
        }
    }
}
