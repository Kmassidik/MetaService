import Foundation
import SQLite3

public enum SQLValue: Equatable {
    case int(Int)
    case real(Double)
    case text(String)
    case null
}

public struct DatabaseError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "sqlite \(code): \(message)" }
    public var isConstraint: Bool { code == SQLITE_CONSTRAINT }
}

public struct Row {
    fileprivate let values: [String: SQLValue]

    public func string(_ column: String) -> String {
        guard case .text(let text)? = values[column] else { return "" }
        return text
    }

    public func optionalString(_ column: String) -> String? {
        guard case .text(let text)? = values[column] else { return nil }
        return text
    }

    public func int(_ column: String) -> Int {
        optionalInt(column) ?? 0
    }

    public func optionalInt(_ column: String) -> Int? {
        guard case .int(let number)? = values[column] else { return nil }
        return number
    }
}

/// One SQLite connection. SQL text must be a string literal (StaticString), so a query can never be
/// built by joining strings; every value goes in through a bound parameter.
public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private static let busyMilliseconds: Int32 = 5000

    public init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            throw DatabaseError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
        }
        sqlite3_busy_timeout(handle, Self.busyMilliseconds)
        try exec("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;")
    }

    deinit { sqlite3_close(handle) }

    /// Run one or more fixed statements that take no parameters.
    public func exec(_ sql: StaticString) throws {
        lock.lock(); defer { lock.unlock() }
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql.description, nil, nil, &message)
        defer { sqlite3_free(message) }
        guard status == SQLITE_OK else { throw DatabaseError(code: status, message: message.map { String(cString: $0) } ?? "exec failed") }
    }

    @discardableResult
    public func execute(_ sql: StaticString, _ params: [SQLValue] = []) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else { throw lastError(status) }
        return Int(sqlite3_changes(handle))
    }

    public func query(_ sql: StaticString, _ params: [SQLValue] = []) throws -> [Row] {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw lastError(status) }
            rows.append(readRow(statement))
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: StaticString, _ params: [SQLValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql.description, -1, &statement, nil)
        guard status == SQLITE_OK else { throw lastError(status) }
        for (index, value) in params.enumerated() { try bind(statement, Int32(index + 1), value) }
        return statement
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: SQLValue) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let status: Int32
        switch value {
        case .int(let number): status = sqlite3_bind_int64(statement, index, Int64(number))
        case .real(let number): status = sqlite3_bind_double(statement, index, number)
        case .text(let text): status = sqlite3_bind_text(statement, index, text, -1, transient)
        case .null: status = sqlite3_bind_null(statement, index)
        }
        guard status == SQLITE_OK else { throw lastError(status) }
    }

    private func readRow(_ statement: OpaquePointer?) -> Row {
        var values: [String: SQLValue] = [:]
        for column in 0..<sqlite3_column_count(statement) {
            let name = String(cString: sqlite3_column_name(statement, column))
            values[name] = readValue(statement, column)
        }
        return Row(values: values)
    }

    private func readValue(_ statement: OpaquePointer?, _ column: Int32) -> SQLValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER: return .int(Int(sqlite3_column_int64(statement, column)))
        case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, column))
        case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(statement, column)))
        default: return .null
        }
    }

    private func lastError(_ status: Int32) -> DatabaseError {
        DatabaseError(code: sqlite3_extended_errcode(handle) & 0xFF == SQLITE_CONSTRAINT ? SQLITE_CONSTRAINT : status,
                      message: String(cString: sqlite3_errmsg(handle)))
    }
}
