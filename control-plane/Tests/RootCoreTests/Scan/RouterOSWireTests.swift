import XCTest
@testable import RootCore

final class RouterOSWireTests: XCTestCase {
    func testLengthEncodingMatchesTheMikroTikDocumentation() {
        XCTAssertEqual(RouterOSWire.encodeLength(0), [0x00])
        XCTAssertEqual(RouterOSWire.encodeLength(0x7F), [0x7F])
        XCTAssertEqual(RouterOSWire.encodeLength(0x80), [0x80, 0x80])
        XCTAssertEqual(RouterOSWire.encodeLength(0x3FFF), [0xBF, 0xFF])
        XCTAssertEqual(RouterOSWire.encodeLength(0x4000), [0xC0, 0x40, 0x00])
        XCTAssertEqual(RouterOSWire.encodeLength(0x1FFFFF), [0xDF, 0xFF, 0xFF])
        XCTAssertEqual(RouterOSWire.encodeLength(0x200000), [0xE0, 0x20, 0x00, 0x00])
    }

    func testSentenceEncoding() {
        XCTAssertEqual(Array(RouterOSWire.encode(sentence: ["/login"])), [6, 0x2F, 0x6C, 0x6F, 0x67, 0x69, 0x6E, 0])
        XCTAssertEqual(Array(RouterOSWire.encode(sentence: [])), [0])
    }

    func testDecoderRoundTripsAllLengthSizes() throws {
        for size in [0, 1, 127, 128, 16_383, 16_384, 70_000] {
            let word = String(repeating: "a", count: size)
            var decoder = RouterOSWire.Decoder()
            let out = try decoder.feed(RouterOSWire.encode(sentence: ["!re", "=k=" + word]))
            XCTAssertEqual(out, [["!re", "=k=" + word]], "size \(size)")
        }
    }

    func testDecoderHandlesBytesArrivingInPiecesAndManySentences() throws {
        let data = RouterOSWire.encode(sentence: ["!re", "=address=192.168.100.5"]) + RouterOSWire.encode(sentence: ["!done"])
        var decoder = RouterOSWire.Decoder()
        var sentences: [[String]] = []
        for byte in data { sentences += try decoder.feed(Data([byte])) }
        XCTAssertEqual(sentences, [["!re", "=address=192.168.100.5"], ["!done"]])
    }

    func testDecoderRefusesHostileInput() {
        var decoder = RouterOSWire.Decoder()
        XCTAssertThrowsError(try decoder.feed(Data([0xF8, 1, 2, 3, 4]))) { XCTAssertEqual($0 as? WireError, .badLength) }
        var big = RouterOSWire.Decoder()
        XCTAssertThrowsError(try big.feed(Data([0xF0, 0x7F, 0xFF, 0xFF, 0xFF]))) { XCTAssertEqual($0 as? WireError, .wordTooLarge) }
        var many = RouterOSWire.Decoder()
        let words = Data((0..<2000).flatMap { _ in [UInt8(1), UInt8(ascii: "x")] })
        XCTAssertThrowsError(try many.feed(words)) { XCTAssertEqual($0 as? WireError, .tooManyWords) }
    }

    func testAttributes() {
        XCTAssertEqual(RouterOSWire.attributes(of: ["!re", "=address=192.168.100.5", "=comment=a=b", "=dynamic=", ".tag=7"]),
                       ["address": "192.168.100.5", "comment": "a=b", "dynamic": ""])
    }

    func testRowsMapLikeTheRestOnes() {
        let rows = [["address": "192.168.100.5", "mac-address": "AA:BB:CC:00:00:05", "host-name": "tv", "status": "bound"], ["address": "192.168.100.6", "disabled": "true"]]
        XCTAssertEqual(RouterOSRows.leases(rows), [RouterEntry(ip: "192.168.100.5", mac: "AA:BB:CC:00:00:05", hostname: "tv")])
    }
}
