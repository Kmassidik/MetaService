// A tiny stand-in for XCTest, for a machine that has only the command line tools (the Mac mini): XCTest itself is not installed there.
// run.py compiles the real sources, the real test files and this file with swiftc, and calls every test method. Only what the tests use is here.
@_exported import Foundation

public var standInFailures: [String] = []
public var standInAssertions = 0

open class XCTestCase {
    // Test classes are called by name from a generated main; XCTest itself is not here.
    public required init() {}
    open func setUpWithError() throws {}
    open func setUp() {}
    open func tearDown() {}
}

public struct StandInSkip: Error {}

private func fail(_ message: String, _ detail: String, _ file: StaticString, _ line: UInt) {
    standInFailures.append("\(file):\(line): \(message) \(detail)")
}

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) { standInAssertions += 1; fail("XCTFail", message, file, line) }

public func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    standInAssertions += 1
    guard let result = try? value(), result else { return fail("XCTAssertTrue failed", message(), file, line) }
}

public func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    standInAssertions += 1
    guard let result = try? value(), !result else { return fail("XCTAssertFalse failed", message(), file, line) }
}

public func XCTAssertEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    standInAssertions += 1
    do {
        let a = try left(), b = try right()
        if a != b { fail("XCTAssertEqual failed: (\(a)) is not equal to (\(b))", message(), file, line) }
    } catch { fail("XCTAssertEqual threw \(error)", message(), file, line) }
}

public func XCTAssertNotEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    standInAssertions += 1
    guard let a = try? left(), let b = try? right(), a == b else { return }
    fail("XCTAssertNotEqual failed: (\(a)) equals (\(b))", message(), file, line)
}

public func XCTAssertLessThan<T: Comparable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    standInAssertions += 1
    guard let a = try? left(), let b = try? right(), a < b else { return fail("XCTAssertLessThan failed", message(), file, line) }
}

public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    standInAssertions += 1
    guard let a = try? left(), let b = try? right(), a >= b else { return fail("XCTAssertGreaterThanOrEqual failed", message(), file, line) }
}

public func XCTAssertNil(_ value: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    standInAssertions += 1
    do {
        if let found = try value() { fail("XCTAssertNil failed: \(found)", message(), file, line) }
    } catch { fail("XCTAssertNil threw \(error)", message(), file, line) }
}

public func XCTAssertNotNil(_ value: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    standInAssertions += 1
    guard let found = try? value(), found != nil else { return fail("XCTAssertNotNil failed", message(), file, line) }
}

public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    standInAssertions += 1
    do {
        _ = try expression()
        fail("XCTAssertThrowsError failed: nothing was thrown", message(), file, line)
    } catch { handler(error) }
}

public func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    standInAssertions += 1
    do { _ = try expression() } catch { fail("XCTAssertNoThrow threw \(error)", message(), file, line) }
}

public func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    standInAssertions += 1
    guard let found = try value() else {
        fail("XCTUnwrap failed", message(), file, line)
        throw StandInSkip()
    }
    return found
}

public func runStandInTest(_ name: String, _ body: () throws -> Void) {
    let before = standInFailures.count
    do { try body() } catch is StandInSkip {} catch { standInFailures.append("\(name) threw \(error)") }
    print(standInFailures.count == before ? "PASS  \(name)" : "FAIL  \(name)")
}

public func finishStandIn() -> Never {
    for failure in standInFailures { print("  - \(failure)") }
    print("\(standInAssertions) assertions, \(standInFailures.count) failures")
    exit(standInFailures.isEmpty ? 0 : 1)
}
