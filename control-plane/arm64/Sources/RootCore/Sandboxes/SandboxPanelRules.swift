import Foundation

/// The operator's side of sandbox teams, keys and the usage page (see `sandbox/README.md`, "Teams, keys and limits" and
/// phase 3's panel pages). Pure: text and numbers in, what to keep or refuse out, so the routes and their tests agree.

/// A key the panel has just made: the text to show once, and the two things that are kept. The text never reaches the
/// database, a log line or a second answer; `prefix` and `secretHash` are what the panel and the API use from then on.
public struct PanelApiKey: Equatable, Sendable {
    public let text: String
    /// `msb_ab12cd34`, for display.
    public let prefix: String
    /// SHA-256 of the secret, in hex.
    public let secretHash: String

    public init(issued: ApiKeyRules.Issued) {
        text = issued.key
        prefix = issued.prefix
        secretHash = issued.secretHash
    }

    /// A fresh key, with a new prefix and 256 bits of secret.
    public static func issue() -> PanelApiKey { PanelApiKey(issued: ApiKeyRules.issue()) }

    /// A fresh id for the key's row. Lowercase letters and digits after a fixed start, so it is the same shape as every
    /// other id in MetaService and a route can check it with `Ids.isValid`.
    public static func newId() -> String {
        "key-" + (0..<newIdCharacters).map { _ in newIdAlphabet[Int.random(in: 0..<newIdAlphabet.count)] }.map(String.init).joined()
    }

    static let newIdCharacters = 16
    private static let newIdAlphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
}

/// The teams the panel makes on demand, so a key is never left without an owner.
public enum SandboxTeamRules {
    /// The team a key belongs to when the operator names none. Created the first time such a key is made.
    public static let defaultTeamName = "Our apps"
    public static let nameMax = 48
    public static let idMax = 32
    /// How many numbered ids are tried before a new team is refused.
    public static let idAttempts = 50
    public static let nameRule = "Use letters, numbers, spaces and - _ . & ( ) ' only, up to \(nameMax) characters."

    private static let allowedNameMarks = CharacterSet(charactersIn: " -_.&()'")
    private static let spaces = " "

    /// A team name as typed, ready to keep: outer spaces gone and runs of spaces made one. Nil when nothing is left, when it
    /// is too long, or when it holds a character the panel does not show.
    public static func cleanName(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let single = trimmed.split(separator: " ", omittingEmptySubsequences: true).joined(separator: spaces)
        guard !single.isEmpty, single.count <= nameMax else { return nil }
        let allowed = CharacterSet.letters.union(.decimalDigits).union(allowedNameMarks)
        guard single.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return single
    }

    /// The id a new team is kept under: its name in lowercase letters, digits and dashes, cut to a sensible length. Never
    /// empty, so `Ids.isValid` holds even for a name written in another alphabet.
    public static func id(from name: String) -> String {
        let dashed = name.lowercased().map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "-"
        }
        let collapsed = String(dashed).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        guard !collapsed.isEmpty else { return fallbackId }
        return String(collapsed.prefix(idMax))
    }

    /// The same id with a number on the end, for a name another team already took. Kept inside `idMax`.
    public static func numbered(_ id: String, _ number: Int) -> String {
        let suffix = "-\(number)"
        return String(id.prefix(max(0, idMax - suffix.count))) + suffix
    }

    private static let fallbackId = "team"
}

/// The window the usage page adds up over. The routes read a number of days, so the page and the route agree.
public enum SandboxUsageWindow {
    public static let defaultDays = 7
    public static let longestDays = 90

    /// The days a request stands for: the default when it says nothing, nil when the number is outside what the page offers.
    public static func days(from requested: Int?) -> Int? {
        guard let requested else { return defaultDays }
        return (1...longestDays).contains(requested) ? requested : nil
    }

    /// Where the window starts: whole days before now, to the second.
    public static func start(now: Date, days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * secondsPerDay)
    }

    static let secondsPerDay: TimeInterval = 24 * 60 * 60
}
