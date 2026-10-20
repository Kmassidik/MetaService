import Foundation

/// A tiny PNG writer (8-bit RGB, no compression) for the simulated screen: no image library is needed and the bytes are the same every time.
enum PngImage {
    static func rgb(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> Data {
        var raw = Data()
        for row in 0..<height {
            raw.append(0)
            for column in 0..<width {
                let color = pixel(column, row)
                raw.append(contentsOf: [color.0, color.1, color.2])
            }
        }
        var header = Data()
        header.append(bigEndian: UInt32(width))
        header.append(bigEndian: UInt32(height))
        header.append(contentsOf: [8, 2, 0, 0, 0])
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(chunk("IHDR", header))
        png.append(chunk("IDAT", zlibStored(raw)))
        png.append(chunk("IEND", Data()))
        return png
    }

    private static func chunk(_ type: String, _ body: Data) -> Data {
        var out = Data()
        out.append(bigEndian: UInt32(body.count))
        let tagged = Data(type.utf8) + body
        out.append(tagged)
        out.append(bigEndian: crc32(tagged))
        return out
    }

    /// zlib stream made of stored (uncompressed) blocks of at most 65535 bytes.
    private static func zlibStored(_ data: Data) -> Data {
        var out = Data([0x78, 0x01])
        var offset = 0
        repeat {
            let size = min(65_535, data.count - offset)
            let last: UInt8 = offset + size >= data.count ? 1 : 0
            out.append(last)
            out.append(contentsOf: [UInt8(size & 0xFF), UInt8(size >> 8), UInt8(~size & 0xFF), UInt8((~size >> 8) & 0xFF)])
            out.append(data[offset..<offset + size])
            offset += size
        } while offset < data.count
        out.append(bigEndian: adler32(data))
        return out
    }

    private static func adler32(_ data: Data) -> UInt32 {
        var low: UInt32 = 1, high: UInt32 = 0
        for byte in data {
            low = (low + UInt32(byte)) % 65_521
            high = (high + low) % 65_521
        }
        return high << 16 | low
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xFFFF_FFFF
        for byte in data { value = crcTable[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8) }
        return value ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
}
