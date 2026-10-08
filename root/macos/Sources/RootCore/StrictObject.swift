import Foundation

public struct InputError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// A JSON object read strictly: unknown keys are refused, and every field is checked for type, size and shape.
public struct StrictObject {
    private let values: [String: Any]
    private let path: String

    public init(data: Data, allowed: Set<String>) throws {
        guard let parsed = try? JSONSerialization.jsonObject(with: data), let object = parsed as? [String: Any] else {
            throw InputError("body must be a JSON object")
        }
        try self.init(object, allowed: allowed, path: "")
    }

    private init(_ object: [String: Any], allowed: Set<String>, path: String) throws {
        if let extra = Set(object.keys).subtracting(allowed).sorted().first {
            throw InputError("unknown field \(path)\(extra)")
        }
        values = object
        self.path = path
    }

    public func has(_ key: String) -> Bool { values[key] != nil && !(values[key] is NSNull) }

    public func string(_ key: String, pattern: Regex<Substring>? = nil, maxLength: Int = 256, minLength: Int = 0) throws -> String {
        guard let text = values[key] as? String, !(values[key] is NSNumber) else { throw InputError("\(path)\(key) must be a string") }
        guard (minLength...maxLength).contains(text.count) else { throw InputError("\(path)\(key) has a bad length") }
        guard pattern == nil || text.wholeMatch(of: pattern!) != nil else { throw InputError("\(path)\(key) has a bad shape") }
        return text
    }

    public func optionalString(_ key: String, maxLength: Int = 256) throws -> String? {
        guard has(key) else { return nil }
        return try string(key, maxLength: maxLength)
    }

    public func id(_ key: String) throws -> String {
        let text = try string(key, maxLength: 63, minLength: 1)
        guard Ids.isValid(text) else { throw InputError("\(path)\(key) is not a valid id") }
        return text
    }

    public func int(_ key: String, range: ClosedRange<Int>) throws -> Int {
        guard let number = values[key] as? NSNumber, !Self.isBoolean(number), number.doubleValue == number.doubleValue.rounded(),
              abs(number.doubleValue) < 9e15 else { throw InputError("\(path)\(key) must be a whole number") }
        guard range.contains(number.intValue) else { throw InputError("\(path)\(key) is out of range") }
        return number.intValue
    }

    public func bool(_ key: String) throws -> Bool {
        guard let number = values[key] as? NSNumber, Self.isBoolean(number) else { throw InputError("\(path)\(key) must be true or false") }
        return number.boolValue
    }

    public func choice(_ key: String, among options: Set<String>) throws -> String {
        let text = try string(key, maxLength: 64)
        guard options.contains(text) else { throw InputError("\(path)\(key) is not an allowed value") }
        return text
    }

    public func object(_ key: String, allowed: Set<String>) throws -> StrictObject {
        guard let child = values[key] as? [String: Any] else { throw InputError("\(path)\(key) must be an object") }
        return try StrictObject(child, allowed: allowed, path: "\(path)\(key)/")
    }

    public func objects(_ key: String, allowed: Set<String>, maxCount: Int) throws -> [StrictObject] {
        guard let list = values[key] as? [Any] else { throw InputError("\(path)\(key) must be a list") }
        guard list.count <= maxCount else { throw InputError("\(path)\(key) has too many items") }
        return try list.enumerated().map { index, item in
            guard let child = item as? [String: Any] else { throw InputError("\(path)\(key)/\(index) must be an object") }
            return try StrictObject(child, allowed: allowed, path: "\(path)\(key)/\(index)/")
        }
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
