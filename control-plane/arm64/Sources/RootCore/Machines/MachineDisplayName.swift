import Foundation
import MSCore

/// The name a person gives a machine to read in the panel ("Mac Studio", "Luca's PC (RTX)"). It is only ever shown as text.
/// Everything that must stay a safe token (links, files, key markers, scripts) uses the machine id, never this name.
public enum MachineDisplayName {
    public static let maxLength = 48
    public static let allowedPunctuation: Set<Character> = ["-", "_", ".", "(", ")", "'", "&"]
    public static let rule = "Use letters, numbers, spaces and - _ . ( ) ' &, up to 48 characters."
    public static let taken = "another machine already has that name"

    /// nil when the name is fine, otherwise the plain words to show.
    public static func problem(_ name: String) -> String? {
        guard !name.isEmpty else { return "Give the machine a name." }
        guard name.count <= maxLength else { return rule }
        guard name.allSatisfy(isAllowed), name.contains(where: { $0.isLetter || isDigit($0) }) else { return rule }
        guard name == name.trimmingCharacters(in: .whitespaces), !name.contains("  ") else { return rule }
        return nil
    }

    public static func checked(_ name: String) throws -> String {
        if let problem = problem(name) { throw InputError(problem) }
        return name
    }

    /// The form used to tell whether two names are the same machine name: no difference in capitals or in how an accent is written.
    public static func comparable(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private static func isAllowed(_ character: Character) -> Bool {
        character.isLetter || isDigit(character) || character == " " || allowedPunctuation.contains(character)
    }
}
