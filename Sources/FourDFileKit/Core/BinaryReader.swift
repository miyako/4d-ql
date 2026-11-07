import Foundation

public enum BinaryReaderError: Error, CustomStringConvertible {
    case truncated(offset: Int, wanted: Int, available: Int)
    public var description: String {
        switch self {
        case .truncated(let o, let w, let a): return "truncated data: wanted \(w) bytes at \(o), \(a) available"
        }
    }
}

/// Bounds-checked cursor over an in-memory buffer.
///
/// Every accessor throws instead of trapping, so a corrupt or unexpected file
/// can never crash the Quick Look extension.
public struct BinaryReader {
    public let data: Data
    public var offset: Int
    public var littleEndian: Bool

    public init(_ data: Data, offset: Int = 0, littleEndian: Bool = true) {
        // Normalise indices so that offset 0 is the first byte.
        self.data = data.startIndex == 0 ? data : Data(data)
        self.offset = offset
        self.littleEndian = littleEndian
    }

    public var remaining: Int { data.count - offset }

    public func peekBytes(at position: Int, count: Int) throws -> Data {
        guard position >= 0, count >= 0, position + count <= data.count else {
            throw BinaryReaderError.truncated(offset: position, wanted: count, available: max(0, data.count - position))
        }
        return data.subdata(in: position..<(position + count))
    }

    public mutating func bytes(_ count: Int) throws -> Data {
        let d = try peekBytes(at: offset, count: count)
        offset += count
        return d
    }

    public mutating func skip(_ count: Int) throws {
        _ = try peekBytes(at: offset, count: count)
        offset += count
    }

    private mutating func integer<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        let d = try bytes(size)
        var value: T = 0
        for (i, byte) in d.enumerated() {
            let shift = littleEndian ? i * 8 : (size - 1 - i) * 8
            value |= T(truncatingIfNeeded: byte) << shift
        }
        return value
    }

    public mutating func u8() throws -> UInt8 { try integer(UInt8.self) }
    public mutating func u16() throws -> UInt16 { try integer(UInt16.self) }
    public mutating func i16() throws -> Int16 { try integer(Int16.self) }
    public mutating func u32() throws -> UInt32 { try integer(UInt32.self) }
    public mutating func i32() throws -> Int32 { try integer(Int32.self) }
    public mutating func i64() throws -> Int64 { try integer(Int64.self) }
    public mutating func f64() throws -> Double { Double(bitPattern: try integer(UInt64.self)) }

    /// 16 raw bytes rendered as upper-case hex, the way 4D writes UUIDs in catalogs.
    public mutating func uuid() throws -> String { try bytes(16).hexString }

    /// UTF-16 string of `count` code units in the reader's byte order.
    public mutating func utf16(count: Int) throws -> String {
        let d = try bytes(count * 2)
        return String(decoding: d.utf16Units(littleEndian: littleEndian), as: UTF16.self)
    }
}

extension Data {
    public var hexString: String { map { String(format: "%02X", $0) }.joined() }

    func utf16Units(littleEndian: Bool) -> [UInt16] {
        stride(from: 0, to: count - 1, by: 2).map { i in
            let a = UInt16(self[startIndex + i]), b = UInt16(self[startIndex + i + 1])
            return littleEndian ? (a | b << 8) : (a << 8 | b)
        }
    }
}
