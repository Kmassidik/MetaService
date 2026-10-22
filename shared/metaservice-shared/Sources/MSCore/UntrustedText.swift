import Foundation

/// Text that came from inside a VM (its log, for example). It is data, never instructions: this keeps only the last few lines,
/// removes escape sequences and control characters, and cuts the result to a size without breaking a character.
public enum UntrustedText {
    private static let escape: Unicode.Scalar = "\u{1B}"
    private static let bell: Unicode.Scalar = "\u{07}"
    private static let newline: Unicode.Scalar = "\n"
    private static let sequenceEnd = 0x40...0x7E

    public static func tail(_ raw: Data, lines: Int, maxBytes: Int) -> String {
        tail(String(decoding: raw, as: UTF8.self), lines: lines, maxBytes: maxBytes)
    }

    public static func tail(_ raw: String, lines: Int, maxBytes: Int) -> String {
        let kept = clean(raw).split(separator: "\n").suffix(lines)
        return cutStart(kept.joined(separator: "\n"), maxBytes: maxBytes)
    }

    private static func clean(_ raw: String) -> String {
        var out = String.UnicodeScalarView()
        var rest = raw.unicodeScalars[...]
        while let scalar = rest.popFirst() {
            if scalar == escape { skipEscapeSequence(&rest); continue }
            if let kept = plain(scalar) { out.append(kept) }
        }
        return String(out)
    }

    /// A tab becomes a space, a new line stays, every other control character goes.
    private static func plain(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        if scalar == newline { return newline }
        if scalar == "\t" { return " " }
        return scalar.properties.generalCategory == .control ? nil : scalar
    }

    /// After ESC: `[` starts a sequence that ends at a letter or symbol, `]` one that ends at BELL or ESC `\`, anything else is one character.
    private static func skipEscapeSequence(_ rest: inout Substring.UnicodeScalarView) {
        guard let kind = rest.popFirst() else { return }
        if kind == "[" { skipControlSequence(&rest) }
        if kind == "]" { skipStringSequence(&rest) }
    }

    private static func skipControlSequence(_ rest: inout Substring.UnicodeScalarView) {
        while let scalar = rest.popFirst() {
            if sequenceEnd.contains(Int(scalar.value)) { return }
        }
    }

    private static func skipStringSequence(_ rest: inout Substring.UnicodeScalarView) {
        while let scalar = rest.popFirst() {
            if scalar == bell { return }
            if scalar == escape { _ = rest.popFirst(); return }
        }
    }

    private static func cutStart(_ text: String, maxBytes: Int) -> String {
        var scalars = text.unicodeScalars[...]
        var size = text.utf8.count
        while size > maxBytes, let dropped = scalars.popFirst() { size -= String(dropped).utf8.count }
        return String(scalars)
    }
}
