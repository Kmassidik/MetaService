import Foundation

public enum WireError: Error, Equatable {
    case wordTooLarge
    case badLength
    case tooManyWords
}

/// The MikroTik binary API (RouterOS 6 and later): sentences made of length-prefixed words, ended by an empty word.
public enum RouterOSWire {
    public static let maxWordBytes = 1 << 20
    public static let maxWordsPerSentence = 1024

    public static func encodeLength(_ length: Int) -> [UInt8] {
        switch length {
        case ..<0x80: return [UInt8(length)]
        case ..<0x4000: return [UInt8((length | 0x8000) >> 8), UInt8(length & 0xFF)]
        case ..<0x200000: return [UInt8((length | 0xC00000) >> 16), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
        case ..<0x10000000: return [UInt8((length | 0xE0000000) >> 24), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
        default: return [0xF0, UInt8((length >> 24) & 0xFF), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
        }
    }

    public static func encode(sentence: [String]) -> Data {
        var bytes: [UInt8] = []
        for word in sentence {
            let raw = Array(word.utf8)
            bytes += encodeLength(raw.count) + raw
        }
        return Data(bytes + [0])
    }

    /// `=name=value` words become a dictionary. Other words (`!re`, `.tag=1`) are not attributes.
    public static func attributes(of sentence: [String]) -> [String: String] {
        var found: [String: String] = [:]
        for word in sentence where word.hasPrefix("=") {
            let body = word.dropFirst()
            guard let split = body.firstIndex(of: "=") else { found[String(body)] = ""; continue }
            found[String(body[..<split])] = String(body[body.index(after: split)...])
        }
        return found
    }

    /// Feed it bytes as they arrive; it hands back every complete sentence.
    public struct Decoder {
        private var buffer: [UInt8] = []
        private var words: [String] = []

        public init() {}

        public mutating func feed(_ data: Data) throws -> [[String]] {
            buffer += data
            var sentences: [[String]] = []
            while let word = try nextWord() {
                guard !word.isEmpty else { sentences.append(words); words = []; continue }
                words.append(word)
                guard words.count <= RouterOSWire.maxWordsPerSentence else { throw WireError.tooManyWords }
            }
            return sentences
        }

        /// The next word, "" for a sentence end, or nil when more bytes are needed.
        private mutating func nextWord() throws -> String? {
            guard let first = buffer.first else { return nil }
            let (length, headerSize) = try Self.length(startingWith: first, in: buffer)
            guard headerSize > 0 else { return nil }
            guard length <= RouterOSWire.maxWordBytes else { throw WireError.wordTooLarge }
            guard buffer.count >= headerSize + length else { return nil }
            let word = String(decoding: buffer[headerSize..<(headerSize + length)], as: UTF8.self)
            buffer.removeFirst(headerSize + length)
            return word
        }

        /// (length, bytes used by the length). The second value is 0 when the length itself is not complete yet.
        private static func length(startingWith first: UInt8, in bytes: [UInt8]) throws -> (Int, Int) {
            let size: Int
            switch first {
            case 0..<0x80: return (Int(first), 1)
            case 0x80..<0xC0: size = 2
            case 0xC0..<0xE0: size = 3
            case 0xE0..<0xF0: size = 4
            case 0xF0: size = 5
            default: throw WireError.badLength
            }
            guard bytes.count >= size else { return (0, 0) }
            let masked = size == 5 ? 0 : Int(first) & (0xFF >> size)
            return (bytes[(size == 5 ? 1 : 1)..<size].reduce(masked) { $0 << 8 | Int($1) }, size)
        }
    }
}
