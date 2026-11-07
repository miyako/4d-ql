import Foundation

/// Every object in a DB4D file is a block that starts with a 28-byte header:
///
///     +0   4cc  tag (stored as an integer, so "DTab" reads "baTD" in a little-endian file)
///     +4   i32  payload length (excluding this header)
///     +8   8    timestamp: u32 ms since midnight, u8 day, u8 month, u16 year
///     +16  u32  checksum
///     +20  i32  position (e.g. table number or record number)
///     +24  i32  parent
struct BlockHeader {
    static let size = 28
    var tag: String
    var length: Int
    var timestamp: DB4DTimestamp
    var position: Int32
}

/// Low-level access to blocks and address tables of a DB4D container.
final class DB4DContainer {
    let source: ByteSource
    let littleEndian: Bool
    /// Non-fatal problems met while walking blocks.
    var warnings: [String] = []

    /// Address tables hold 1024 entries of (i64 address, i32 length). Negative or
    /// zero addresses are free-list links. An entry pointing at another
    /// TabA/Taba block is a second level (used once a table outgrows 1024 entries).
    static let entriesPerAddressTable = 1024
    static let addressEntrySize = 12
    static let addressTableTags: Set<String> = ["TabA", "Taba"]

    init(source: ByteSource, littleEndian: Bool) {
        self.source = source
        self.littleEndian = littleEndian
    }

    func reader(_ data: Data) -> BinaryReader { BinaryReader(data, littleEndian: littleEndian) }

    func isValidAddress(_ a: Int64) -> Bool { a > 0 && a + Int64(BlockHeader.size) <= source.size }

    func blockHeader(at address: Int64) throws -> BlockHeader {
        try parseBlockHeader(try source.read(at: address, length: BlockHeader.size))
    }

    func parseBlockHeader(_ d: Data) throws -> BlockHeader {
        var r = reader(d)
        let tagBytes = [UInt8](try r.bytes(4))
        let tag = String(decoding: littleEndian ? tagBytes.reversed() : tagBytes, as: UTF8.self)
        let length = Int(try r.i32())
        let ms = Int(try r.u32()), day = Int(try r.u8()), month = Int(try r.u8()), year = Int(try r.u16())
        try r.skip(4)
        let pos = try r.i32()
        return BlockHeader(tag: tag, length: length,
                           timestamp: DB4DTimestamp(year: year, month: month, day: day, milliseconds: ms),
                           position: pos)
    }

    /// Reads a whole block (header + payload), capped at `maxLength` bytes.
    func block(at address: Int64, expectedLength: Int? = nil, maxLength: Int = 1 << 20) throws -> (BlockHeader, Data) {
        let header = try blockHeader(at: address)
        let total = min(BlockHeader.size + max(0, header.length), maxLength)
        let data = try source.readAvailable(at: address, length: total)
        return (header, data)
    }

    struct Entry { var index: Int; var address: Int64; var length: Int }

    /// Flattens an address table (following nested TabA levels) into its live entries.
    /// `visit` returns false to stop early.
    func walkAddressTable(at address: Int64, depth: Int = 0, firstIndex: Int = 0,
                          visit: (Entry, BlockHeader) throws -> Bool) throws -> Bool {
        guard isValidAddress(address), depth < 4 else { return true }
        let header = try blockHeader(at: address)
        guard Self.addressTableTags.contains(header.tag) else { return true }
        let count = Self.entriesPerAddressTable
        let raw = try source.readAvailable(at: address + Int64(BlockHeader.size), length: count * Self.addressEntrySize)
        var r = reader(raw)
        let available = raw.count / Self.addressEntrySize
        for i in 0..<available {
            let a = try r.i64()
            let len = Int(try r.i32())
            guard isValidAddress(a) else { continue }
            let child = try blockHeader(at: a)
            if Self.addressTableTags.contains(child.tag) {
                // Nested level (two-level tables: each child covers `count` entries).
                if try !walkAddressTable(at: a, depth: depth + 1, firstIndex: (firstIndex + i) * count, visit: visit) { return false }
            } else if try !visit(Entry(index: firstIndex + i, address: a, length: len), child) {
                return false
            }
        }
        return true
    }

    /// Length-prefixed UTF-16 name. The prefix is i16 in table/field definitions
    /// and i32 (sometimes negated) in relation and index definitions.
    func name(_ r: inout BinaryReader, wideLength: Bool, maxChars: Int) throws -> String {
        let n = wideLength ? Int(try r.i32()) : Int(try r.i16())
        let count = min(abs(n), maxChars)
        guard count > 0 else { return "" }
        return try r.utf16(count: count)
    }
}
