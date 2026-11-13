import Foundation

/// Reads the name of the primary network interface (the one that holds the default route) from the output of `route -n get default`. Pure: running the command is the caller's job.
public enum PrimaryInterface {
    private static let interfaceKey = "interface:"
    private static let symbolsInName: Set<Character> = [".", "_", "-"]

    /// The name after `interface:`, or nil when there is no such line, the name is empty, or it holds anything but ASCII letters, digits, `.`, `_` or `-`.
    public static func parse(routeOutput: String) -> String? {
        let lines = routeOutput.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line = lines.first(where: { $0.hasPrefix(interfaceKey) }) else { return nil }
        let name = line.dropFirst(interfaceKey.count).trimmingCharacters(in: .whitespaces)
        return isValidName(name) ? name : nil
    }

    /// A name is valid when it is not empty and every character is allowed.
    private static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.allSatisfy(isAllowed)
    }

    /// One character of an interface name: ASCII letter or digit, or one of the few symbols interface names use.
    private static func isAllowed(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || symbolsInName.contains(character)
    }
}
