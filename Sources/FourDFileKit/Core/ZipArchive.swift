import Foundation
#if canImport(Compression)
import Compression
#endif

public enum ZipError: Error, CustomStringConvertible {
    case invalid(String)
    case unsupported(String)
    case tooLarge(String)

    public var description: String {
        switch self {
        case .invalid(let message): return "invalid ZIP archive: \(message)"
        case .unsupported(let message): return "unsupported ZIP feature: \(message)"
        case .tooLarge(let message): return "ZIP entry is too large: \(message)"
        }
    }
}

/// A read-only ZIP reader for small document archives (stored and deflated
/// entries only). Every size comes from the central directory and is checked
/// against the file and the caller's limits before anything is decompressed.
public struct ZipArchive {
    public struct Entry: Encodable {
        public var name: String
        public var method: UInt16
        public var compressedSize: Int
        public var uncompressedSize: Int
        public var crc32: UInt32
        var flags: UInt16
        var localHeaderOffset: Int64
        public var isDirectory: Bool { name.hasSuffix("/") }
    }

    public let source: ByteSource
    public let entries: [Entry]

    public static func looksLikeZip(_ source: ByteSource) -> Bool {
        guard let head = try? source.readAvailable(at: 0, length: 4) else { return false }
        return head.elementsEqual([0x50, 0x4B, 0x03, 0x04]) || head.elementsEqual([0x50, 0x4B, 0x05, 0x06])
    }

    public init(_ source: ByteSource, maxEntries: Int = 4_096) throws {
        self.source = source
        guard source.size >= 22 else { throw ZipError.invalid("file is shorter than an end-of-central-directory record") }
        let tailLength = Int(min(source.size, 22 + 65_535))
        let tail = [UInt8](try source.read(at: source.size - Int64(tailLength), length: tailLength))
        guard let eocd = stride(from: tail.count - 22, through: 0, by: -1).first(where: {
            tail[$0] == 0x50 && tail[$0 + 1] == 0x4B && tail[$0 + 2] == 0x05 && tail[$0 + 3] == 0x06
        }) else { throw ZipError.invalid("end-of-central-directory record not found") }
        let count = Int(Self.u16(tail, eocd + 10))
        let directorySize = Int64(Self.u32(tail, eocd + 12))
        let directoryOffset = Int64(Self.u32(tail, eocd + 16))
        guard count != 0xFFFF, directoryOffset != 0xFFFF_FFFF else { throw ZipError.unsupported("ZIP64 archives") }
        guard count <= maxEntries else { throw ZipError.tooLarge("\(count) entries exceed the limit of \(maxEntries)") }
        guard directoryOffset + directorySize <= source.size, directorySize <= 16 * 1024 * 1024 else {
            throw ZipError.invalid("central directory lies outside the file")
        }
        let directory = [UInt8](try source.read(at: directoryOffset, length: Int(directorySize)))
        var entries: [Entry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= directory.count, Self.u32(directory, p) == 0x0201_4B50 else {
                throw ZipError.invalid("central directory entry is truncated")
            }
            let flags = Self.u16(directory, p + 8)
            let nameLength = Int(Self.u16(directory, p + 28))
            let extraLength = Int(Self.u16(directory, p + 30))
            let commentLength = Int(Self.u16(directory, p + 32))
            guard p + 46 + nameLength + extraLength + commentLength <= directory.count else {
                throw ZipError.invalid("central directory entry is truncated")
            }
            let nameBytes = directory[(p + 46)..<(p + 46 + nameLength)]
            let name = String(bytes: nameBytes, encoding: .utf8) ?? String(decoding: nameBytes, as: UTF8.self)
            entries.append(Entry(name: name, method: Self.u16(directory, p + 10),
                                 compressedSize: Int(Self.u32(directory, p + 20)),
                                 uncompressedSize: Int(Self.u32(directory, p + 24)),
                                 crc32: Self.u32(directory, p + 16), flags: flags,
                                 localHeaderOffset: Int64(Self.u32(directory, p + 42))))
            p += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    public func entry(named name: String) -> Entry? { entries.first { $0.name == name } }

    /// Decompresses one entry, refusing entries whose declared size exceeds `limit`.
    public func data(for entry: Entry, limit: Int) throws -> Data {
        guard entry.flags & 1 == 0 else { throw ZipError.unsupported("encrypted entry \(entry.name)") }
        guard entry.uncompressedSize <= limit else {
            throw ZipError.tooLarge("\(entry.name) is \(entry.uncompressedSize) bytes (limit \(limit))")
        }
        let header = [UInt8](try source.read(at: entry.localHeaderOffset, length: 30))
        guard Self.u32(header, 0) == 0x0403_4B50 else { throw ZipError.invalid("local header of \(entry.name) not found") }
        let start = entry.localHeaderOffset + 30 + Int64(Self.u16(header, 26)) + Int64(Self.u16(header, 28))
        guard start + Int64(entry.compressedSize) <= source.size else { throw ZipError.invalid("\(entry.name) is truncated") }
        let compressed = try source.read(at: start, length: entry.compressedSize)
        let output: [UInt8]
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.uncompressedSize else { throw ZipError.invalid("stored size mismatch in \(entry.name)") }
            output = [UInt8](compressed)
        case 8:
            output = try Self.inflate([UInt8](compressed), expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupported("compression method \(entry.method) in \(entry.name)")
        }
        guard output.count == entry.uncompressedSize else { throw ZipError.invalid("\(entry.name) has the wrong decompressed size") }
        guard CRC32.checksum(output) == entry.crc32 else { throw ZipError.invalid("\(entry.name) fails its CRC check") }
        return Data(output)
    }

    static func inflate(_ input: [UInt8], expectedSize: Int) throws -> [UInt8] {
        #if canImport(Compression)
        if expectedSize == 0 { return [] }
        var output = [UInt8](repeating: 0, count: expectedSize)
        let written = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(destination.baseAddress!, expectedSize, source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        if written == expectedSize { return output }
        #endif
        return try Inflater.inflate(input, limit: expectedSize)
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

/// Portable raw DEFLATE (RFC 1951) decoder used where Apple's Compression
/// framework is unavailable. Output never exceeds `limit` bytes.
enum Inflater {
    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int]

        init(lengths: [Int]) throws {
            symbols = [Int](repeating: 0, count: lengths.count)
            for length in lengths { counts[length] += 1 }
            counts[0] = 0
            var left = 1
            for length in 1...15 {
                left = left << 1 - counts[length]
                guard left >= 0 else { throw ZipError.invalid("over-subscribed Huffman code") }
            }
            var offsets = [Int](repeating: 0, count: 16)
            for length in 1..<15 { offsets[length + 1] = offsets[length] + counts[length] }
            for (symbol, length) in lengths.enumerated() where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
        }
    }

    private struct Reader {
        let input: [UInt8]
        var position = 0
        var bitBuffer = 0
        var bitCount = 0

        mutating func bits(_ need: Int) throws -> Int {
            while bitCount < need {
                guard position < input.count else { throw ZipError.invalid("deflate stream ends early") }
                bitBuffer |= Int(input[position]) << bitCount
                position += 1
                bitCount += 8
            }
            let value = bitBuffer & ((1 << need) - 1)
            bitBuffer >>= need
            bitCount -= need
            return value
        }

        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for length in 1...15 {
                code |= try bits(1)
                let count = h.counts[length]
                if code - count < first { return h.symbols[index + code - first] }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            throw ZipError.invalid("invalid Huffman code")
        }
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let fixed: (Huffman, Huffman) = {
        var lengths = [Int](repeating: 8, count: 288)
        for i in 144..<256 { lengths[i] = 9 }
        for i in 256..<280 { lengths[i] = 7 }
        // The fixed tables are complete by construction.
        return (try! Huffman(lengths: lengths), try! Huffman(lengths: [Int](repeating: 5, count: 30)))
    }()

    static func inflate(_ input: [UInt8], limit: Int) throws -> [UInt8] {
        var reader = Reader(input: input)
        var output: [UInt8] = []
        output.reserveCapacity(min(limit, 64 * 1024 * 1024))
        var last = 0
        repeat {
            last = try reader.bits(1)
            switch try reader.bits(2) {
            case 0:
                reader.bitBuffer = 0
                reader.bitCount = 0
                guard reader.position + 4 <= input.count else { throw ZipError.invalid("stored block is truncated") }
                let length = Int(input[reader.position]) | Int(input[reader.position + 1]) << 8
                let complement = Int(input[reader.position + 2]) | Int(input[reader.position + 3]) << 8
                guard length == ~complement & 0xFFFF else { throw ZipError.invalid("stored block length mismatch") }
                reader.position += 4
                guard reader.position + length <= input.count else { throw ZipError.invalid("stored block is truncated") }
                guard output.count + length <= limit else { throw ZipError.tooLarge("deflate output exceeds \(limit) bytes") }
                output += input[reader.position..<(reader.position + length)]
                reader.position += length
            case 1:
                try codes(&reader, &output, fixed.0, fixed.1, limit: limit)
            case 2:
                let literalCount = try reader.bits(5) + 257
                let distanceCount = try reader.bits(5) + 1
                let codeCount = try reader.bits(4) + 4
                guard literalCount <= 286, distanceCount <= 30 else { throw ZipError.invalid("bad dynamic block counts") }
                let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var codeLengths = [Int](repeating: 0, count: 19)
                for i in 0..<codeCount { codeLengths[order[i]] = try reader.bits(3) }
                let lengthCode = try Huffman(lengths: codeLengths)
                var lengths: [Int] = []
                while lengths.count < literalCount + distanceCount {
                    let symbol = try reader.decode(lengthCode)
                    switch symbol {
                    case 0..<16: lengths.append(symbol)
                    case 16:
                        guard let previous = lengths.last else { throw ZipError.invalid("repeat without a previous length") }
                        lengths += [Int](repeating: previous, count: 3 + (try reader.bits(2)))
                    case 17: lengths += [Int](repeating: 0, count: 3 + (try reader.bits(3)))
                    default: lengths += [Int](repeating: 0, count: 11 + (try reader.bits(7)))
                    }
                }
                guard lengths.count == literalCount + distanceCount, lengths[256] != 0 else {
                    throw ZipError.invalid("bad dynamic code lengths")
                }
                try codes(&reader, &output, try Huffman(lengths: Array(lengths[0..<literalCount])),
                          try Huffman(lengths: Array(lengths[literalCount...])), limit: limit)
            default:
                throw ZipError.invalid("reserved deflate block type")
            }
        } while last == 0
        return output
    }

    private static func codes(_ reader: inout Reader, _ output: inout [UInt8], _ literal: Huffman, _ distance: Huffman, limit: Int) throws {
        while true {
            let symbol = try reader.decode(literal)
            if symbol < 256 {
                guard output.count < limit else { throw ZipError.tooLarge("deflate output exceeds \(limit) bytes") }
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let index = symbol - 257
                guard index < 29 else { throw ZipError.invalid("bad length symbol") }
                let length = lengthBase[index] + (try reader.bits(lengthExtra[index]))
                let distanceSymbol = try reader.decode(distance)
                guard distanceSymbol < 30 else { throw ZipError.invalid("bad distance symbol") }
                let back = distanceBase[distanceSymbol] + (try reader.bits(distanceExtra[distanceSymbol]))
                guard back <= output.count else { throw ZipError.invalid("distance reaches before the output start") }
                guard output.count + length <= limit else { throw ZipError.tooLarge("deflate output exceeds \(limit) bytes") }
                let start = output.count - back
                for i in 0..<length { output.append(output[start + i]) }
            }
        }
    }
}
