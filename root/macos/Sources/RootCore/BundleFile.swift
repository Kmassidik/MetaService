import Foundation

/// The file name of a chat bundle: metaservice-chat-<version>-<platform>.tar.gz. Anything else is not a bundle.
public struct BundleFile: Equatable {
    public let version: String
    public let platform: String

    private static let pattern = #/^metaservice-chat-(\d{1,4}\.\d{1,4}\.\d{1,4})-(noarch|(?:macos|linux)-(?:arm64|aarch64|x86_64))\.tar\.gz$/#

    public init?(fileName: String) {
        guard let match = fileName.wholeMatch(of: Self.pattern) else { return nil }
        version = String(match.output.1)
        platform = String(match.output.2)
    }

    public static func fileName(version: String, platform: String) -> String {
        "metaservice-chat-\(version)-\(platform).tar.gz"
    }

    /// True when `first` is an older version than `second`.
    public static func isOlder(_ first: String, than second: String) -> Bool {
        let a = first.split(separator: ".").compactMap { Int($0) }, b = second.split(separator: ".").compactMap { Int($0) }
        return a.lexicographicallyPrecedes(b)
    }
}
