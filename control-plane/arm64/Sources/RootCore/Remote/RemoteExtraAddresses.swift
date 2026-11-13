import Foundation

/// The owner's extra addresses for Add machine (ROOT_REMOTE_EXTRA_ADDRESSES): exact IPv4 text, comma separated.
/// Parsing never fails: an item that cannot be used is skipped, so a typo can only drop that one address.
public enum RemoteExtraAddresses {
    /// The most addresses the owner may list. Anything beyond this is dropped.
    public static let maxCount = 8
    private static let separator: Character = ","
    private static let unspecifiedAddress = "0.0.0.0"
    private static let broadcastAddress = "255.255.255.255"

    /// Turns the list into a set of exact addresses: spaces trimmed, empty, invalid, loopback, unspecified, broadcast and repeated items dropped, first `maxCount` kept.
    public static func parse(_ text: String) -> Set<String> {
        let usable = text.split(separator: separator).compactMap { usableAddress(String($0)) }
        var seen = Set<String>()
        let unique = usable.filter { seen.insert($0).inserted }
        return Set(unique.prefix(maxCount))
    }

    /// The trimmed item when it is a valid address the owner may add, otherwise nil.
    private static func usableAddress(_ item: String) -> String? {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        guard IPv4.isValid(trimmed), !IPv4.isLoopback(trimmed) else { return nil }
        guard trimmed != unspecifiedAddress, trimmed != broadcastAddress else { return nil }
        return trimmed
    }
}
