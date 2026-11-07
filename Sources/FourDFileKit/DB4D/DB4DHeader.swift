import Foundation

/// File header of a DB4D container (first 256 bytes of .4DD / .4DB / .4DIndx).
///
/// Layout derived from DataInfo.readFileInfo in github.com/miyako/DataAnalyzer
/// (after JPR's 2015 tech note) and checked against real files. All values are
/// in the byte order given by the signature.
///
///     0x00  u32  signature 02 44 01 44 (in file order => little endian)
///     0x04  i32  last operation (0 = flushed, -1 = interrupted)
///     0x08  u32  last parameter
///     0x0C  i16  number of segments, i16 (unused)
///     0x10  i32  sub-version     0x14 i32 version
///     0x18  16   database UUID (identical in a .4DB and its .4DD)
///     0x28  i64  logical EOF     0x30 i64 segment limit
///     0x38  i64  secondary block-allocation table
///     0x40  i32  block size      0x44 i32 ratio (log2 of block size)
///     0x48  i64  address of the data-table (DTab) address table
///     0x50  i64  segment headers 0x58 i32 segment header size
///     0x5C  u32  random stamp    0x60 i32 header modification count
///     0x64  i64  last journal action number
///     0x6C  i32  number of journal files
///     0x70  u32  last flush random stamp
///     0x74  i32  number of data tables
///     0x78  u8×4 flags: [0] needs repair, [2] contains structure, [3] indexes in separate file
///     0x7C  i64  first free entry of the table-definition address table (-2e9 = none)
///     0x84  i64  table-definition (TDEF) address table   0x8C i32 count
///     0x90  i32  relation count  0x94 i64 first free  0x9C i64 relation (RDEF) table
///     0xA4  i32  sequence count  0xA8 i64 first free  0xB0 i64 sequence table
///     0xB8  i32  index count     0xBC i64 first free  0xC4 i64 index (iDEF) table
///     0xCC  i32  structure index count  0xD0 i64 first free  0xD8 i64 IDEF table
///     0xE0  i64  extra properties (xDAT) address   0xE8 i32 extra properties length
///     0xEC  i64  first free entry of the address-table table
///     0xF4  i32  flush count     0xF8 i32 dialect (Windows LCID)
///     0xFC  u8   collation flags
struct RawHeader {
    var header: DB4DHeader
    var dataTablesAddress: Int64
    var tableDefinitionsAddress: Int64
    var relationsAddress: Int64
    var indexesAddress: Int64
    var extraAddress: Int64
    var extraLength: Int
}

enum DB4DSignature {
    static let little: [UInt8] = [0x02, 0x44, 0x01, 0x44]
    static let big: [UInt8] = [0x44, 0x01, 0x44, 0x02]
    static let legacyMac: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
    static let legacyWin: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFE]

    /// nil if the file is not a DB4D container.
    static func byteOrder(of source: ByteSource) -> Bool? {
        guard let d = try? source.read(at: 0, length: 4) else { return nil }
        let b = [UInt8](d)
        if b == little { return true }
        if b == big { return false }
        return nil
    }

    static func isLegacy(_ source: ByteSource) -> Bool {
        guard let d = try? source.read(at: 0, length: 4) else { return false }
        return [UInt8](d) == legacyMac || [UInt8](d) == legacyWin
    }
}

extension RawHeader {
    static let size = 256

    init(source: ByteSource) throws {
        guard let le = DB4DSignature.byteOrder(of: source) else {
            if DB4DSignature.isLegacy(source) {
                throw AnalyzerError.notRecognized("\(source.url.lastPathComponent) (4D v6 or older format)")
            }
            throw AnalyzerError.notRecognized(source.url.lastPathComponent)
        }
        var r = BinaryReader(try source.read(at: 0, length: Self.size), littleEndian: le)

        try r.skip(4)
        let lastOperation = try r.i32()
        try r.skip(4)
        let segments = Int(try r.i16())
        try r.skip(2)
        let sub = try r.i32(), ver = try r.i32()
        let uuid = try r.uuid()
        let eof = try r.i64()
        try r.skip(16)                                   // segment limit, secondary BAT
        let blockSize = Int(try r.i32())
        try r.skip(4)                                    // ratio
        let dataTables = try r.i64()
        try r.skip(8 + 4 + 4)                            // segment headers, size, stamp
        let hdrMods = Int(try r.i32())
        let lastLog = try r.i64()
        let logFiles = Int(try r.i32())
        try r.skip(4)
        let nbDataTables = Int(try r.i32())
        let flags = [UInt8](try r.bytes(4))
        try r.skip(8)
        let tdefAddr = try r.i64()
        let nbTDEF = Int(try r.i32())
        let nbRel = Int(try r.i32())
        try r.skip(8)
        let relAddr = try r.i64()
        let nbSeq = Int(try r.i32())
        try r.skip(16)
        let nbIdx = Int(try r.i32())
        try r.skip(8)
        let idxAddr = try r.i64()
        let nbIdxS = Int(try r.i32())
        try r.skip(16)
        let extraAddr = try r.i64()
        let extraLen = Int(try r.i32())
        try r.skip(8)
        let flushes = Int(try r.i32())
        let dialect = try r.i32()
        let collation = try r.u8()

        // A valid signature followed by nonsense means a damaged or foreign file.
        guard blockSize >= 32, blockSize <= 65_536, blockSize & (blockSize - 1) == 0,
              (1...255).contains(segments), eof >= 0 else {
            throw AnalyzerError.notRecognized("\(source.url.lastPathComponent) (header is damaged)")
        }

        var localeID: String?
        if dialect > 0 {
            localeID = Locale.identifier(fromWindowsLocaleCode: Int(dialect))
        }

        header = DB4DHeader(
            littleEndian: le, lastOperation: lastOperation, segmentCount: segments,
            formatVersion: "\(ver).\(sub)", databaseUUID: uuid, logicalEOF: eof,
            blockSize: blockSize, headerModificationCount: hdrMods,
            lastJournalAction: lastLog, journalFileCount: logFiles, dataTableCount: nbDataTables,
            needsRepair: flags[0] == 1, indexesInSeparateFile: flags[3] == 1,
            tableDefinitionCount: nbTDEF, relationCount: nbRel, sequenceCount: nbSeq,
            indexCount: nbIdx, structureIndexCount: nbIdxS, flushCount: flushes,
            dialectCode: dialect, dialectLocaleIdentifier: localeID,
            collation: CollationOptions(collation))
        dataTablesAddress = dataTables
        tableDefinitionsAddress = tdefAddr
        relationsAddress = relAddr
        indexesAddress = idxAddr
        extraAddress = extraAddr
        extraLength = extraLen
    }
}
