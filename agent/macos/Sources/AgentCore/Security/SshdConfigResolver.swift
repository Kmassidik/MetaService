import Foundation

/// Reads files for the resolver. A test answers from a dictionary; the real one reads the disk.
public protocol SshdConfigFiles {
    /// The text of a file, or nil when it cannot be read.
    func read(_ path: String) -> String?
    /// The files a glob pattern matches, sorted by name. Empty when nothing matches.
    func expand(_ pattern: String) -> [String]
}

/// The effective `PasswordAuthentication` of sshd, worked out the way sshd reads its configuration: the first value wins, `Include` is read
/// where it stands, `Match` blocks are skipped (they depend on who connects), and with no value the answer is the default, yes.
/// KbdInteractiveAuthentication (password through PAM) is not looked at: this answers the PasswordAuthentication setting only.
public struct SshdConfigResolver {
    public static let mainConfig = "/etc/ssh/sshd_config"
    public static let configDirectory = "/etc/ssh"
    /// sshd stops following Include after this many levels.
    static let maxIncludeDepth = 16
    private static let keyword = "passwordauthentication"
    private static let includeKeyword = "include"
    private static let matchKeyword = "match"

    public let files: SshdConfigFiles
    public init(files: SshdConfigFiles) { self.files = files }

    private enum Found { case value(Bool), invalid, unreadable, nothing }

    /// true: password login is on; false: off; nil: the configuration could not be read, or says something sshd would refuse.
    public func passwordLogin() -> Bool? {
        switch scan(Self.mainConfig, depth: 0) {
        case .value(let on): return on
        case .nothing: return true
        case .invalid, .unreadable: return nil
        }
    }

    private func scan(_ path: String, depth: Int) -> Found {
        guard depth <= Self.maxIncludeDepth else { return .invalid }
        guard let text = files.read(path) else { return .unreadable }
        for line in text.split(whereSeparator: \.isNewline) {
            let words = Self.words(of: line)
            guard let first = words.first?.lowercased() else { continue }
            if first == Self.matchKeyword { return .nothing }
            let found = first == Self.includeKeyword ? include(Array(words.dropFirst()), depth: depth) : value(first, words)
            if case .nothing = found { continue }
            return found
        }
        return .nothing
    }

    private func include(_ patterns: [String], depth: Int) -> Found {
        for pattern in patterns {
            let absolute = pattern.hasPrefix("/") ? pattern : Self.configDirectory + "/" + pattern
            for path in files.expand(absolute) {
                let found = scan(path, depth: depth + 1)
                if case .nothing = found { continue }
                return found
            }
        }
        return .nothing
    }

    private func value(_ first: String, _ words: [String]) -> Found {
        guard first == Self.keyword else { return .nothing }
        switch words.dropFirst().first?.lowercased() {
        case "yes": return .value(true)
        case "no": return .value(false)
        default: return .invalid
        }
    }

    /// The words of one line: comments cut, `keyword=value` and quotes understood the way sshd does.
    static func words(of line: Substring) -> [String] {
        var words: [String] = []
        var current = ""
        var quoted = false
        var started = false
        for character in line {
            if character == "#" && !quoted { break }
            if character == "\"" { quoted.toggle(); started = true; continue }
            let isSeparator = !quoted && (character == " " || character == "\t" || isEqualsAfterKeyword(character, words: words, started: started))
            guard isSeparator else { current.append(character); started = true; continue }
            if started { words.append(current) }
            current = ""
            started = false
        }
        if started { words.append(current) }
        return words
    }

    /// `Keyword=value` and `Keyword = value`: the first `=` after the keyword separates it from its value.
    private static func isEqualsAfterKeyword(_ character: Character, words: [String], started: Bool) -> Bool {
        guard character == "=" else { return false }
        return words.isEmpty ? started : (words.count == 1 && !started)
    }
}
