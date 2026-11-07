import Foundation

/// Table definition (TDEF block). Offsets relative to the block start:
///
///     +28   16   table UUID
///     +44   i16 + 31×UTF-16  table name
///     +202  u8   1 = table is "encryptable" in the structure (not proof that its data is encrypted)
///     +212  i32  number of field slots
///     +244  field slots, 132 bytes each:
///           +0    16   field UUID (all zero = deleted field)
///           +16   i16 + 31×UTF-16  field name
///           +108  i32  limiting length (meaningful for Alpha only)
///           +116  i32  field type (catalog.4DCatalog numbering)
///
/// Table definitions are never encrypted, even in an encrypted data file.
struct TableDefinition {
    var index: Int
    var uuid: String
    var name: String
    var fields: [FieldInfo]
    var encryptable: Bool
}

/// Data table header (DTab block). Offsets relative to the block start:
///
///     +20  i32  table number (block position)
///     +28  i32  number of records
///     +44  i64  address of the record address table
///     +64  i64  address of the blob address table
///     +72  i32  number of blobs
///     +92  16   UUID of the table definition
struct DataTable {
    var number: Int
    var uuid: String
    var recordCount: Int
    var blobCount: Int
    var recordTableAddress: Int64
    var timestamp: DB4DTimestamp
    /// Block tag of the first live record ("rec1" plain, "recx" encrypted), nil if none.
    var firstRecordTag: String?
}

/// Encrypted records and blobs keep their 28-byte block header in clear text but
/// change tag: "rec1" -> "recx", "blob" -> "blbx". The payload is AES-encrypted
/// with the data key and cannot be read without it.
enum DataBlockTag {
    static let plainRecord = "rec1"
    static let encryptedRecord = "recx"
    static let encryptedBlob = "blbx"
}

extension DB4DContainer {
    static let tableNameOffset = 44
    static let encryptableOffset = 202
    static let fieldCountOffset = 212
    static let firstFieldOffset = 244
    static let fieldSlotSize = 132
    static let maxNameChars = 31

    func tableDefinitions(at address: Int64) throws -> [TableDefinition] {
        var result: [TableDefinition] = []
        _ = try walkAddressTable(at: address) { entry, header in
            guard header.tag == "TDEF" else { return true }
            do {
                let (_, data) = try block(at: entry.address)
                result.append(try parseTableDefinition(data, index: entry.index))
            } catch {
                warnings.append("table definition #\(entry.index + 1): \(error)")
            }
            return true
        }
        return result
    }

    func parseTableDefinition(_ data: Data, index: Int) throws -> TableDefinition {
        var r = reader(data)
        r.offset = BlockHeader.size
        let uuid = try r.uuid()
        let name = try self.name(&r, wideLength: false, maxChars: Self.maxNameChars)
        r.offset = Self.encryptableOffset
        let encryptable = try r.u8() != 0
        r.offset = Self.fieldCountOffset
        let slots = Int(try r.i32())
        var fields: [FieldInfo] = []
        for slot in 0..<max(0, min(slots, 4096)) {
            let base = Self.firstFieldOffset + slot * Self.fieldSlotSize
            guard base + Self.fieldSlotSize <= data.count else { break }
            r.offset = base
            let fuuid = try r.uuid()
            if fuuid == String(repeating: "0", count: 32) { continue } // deleted field
            let fname = try self.name(&r, wideLength: false, maxChars: Self.maxNameChars)
            r.offset = base + 108
            let limit = Int(try r.i32())
            r.offset = base + 116
            let type = Int(try r.i32())
            // Deleted slots do not always clear their UUID; they keep type 0 and no name.
            if type == 0 && fname.isEmpty { continue }
            fields.append(FieldInfo(number: slot + 1, name: fname, uuid: fuuid, typeCode: type,
                                    limitingLength: (type == FieldKind.text.rawValue && limit > 0) ? limit : nil))
        }
        return TableDefinition(index: index, uuid: uuid, name: name, fields: fields, encryptable: encryptable)
    }

    /// Tag of the first live block in an address table (one table read, one header read).
    func firstEntryTag(at address: Int64) -> String? {
        var tag: String?
        _ = try? walkAddressTable(at: address) { _, header in
            tag = header.tag
            return false
        }
        return tag
    }

    func dataTables(at address: Int64) throws -> [DataTable] {
        var result: [DataTable] = []
        _ = try walkAddressTable(at: address) { entry, header in
            guard header.tag == "DTab" else { return true }
            do {
                let data = try source.read(at: entry.address, length: 108)
                var r = reader(data)
                r.offset = 28; let nrec = Int(try r.i32())
                r.offset = 44; let recTab = try r.i64()
                r.offset = 72; let nblob = Int(try r.i32())
                r.offset = 92; let uuid = try r.uuid()
                result.append(DataTable(number: Int(header.position), uuid: uuid, recordCount: nrec,
                                        blobCount: nblob, recordTableAddress: recTab, timestamp: header.timestamp,
                                        firstRecordTag: nrec > 0 ? firstEntryTag(at: recTab) : nil))
            } catch {
                warnings.append("data table #\(entry.index + 1): \(error)")
            }
            return true
        }
        return result
    }

    /// Relation definition (RDEF block):
    ///
    ///     +28 16 relation UUID, +44 16 source field UUID, +60 16 destination field UUID,
    ///     +96 i32 + UTF-16 name, then i32 + UTF-16 inverse name
    func relations(at address: Int64, fieldNames: [String: String]) throws -> [RelationInfo] {
        var result: [RelationInfo] = []
        _ = try walkAddressTable(at: address) { entry, header in
            guard header.tag == "RDEF" else { return true }
            do {
                let (_, data) = try block(at: entry.address)
                var r = reader(data)
                r.offset = 44
                let src = try r.uuid(), dst = try r.uuid()
                r.offset = 96
                let name = try self.name(&r, wideLength: true, maxChars: 255)
                let inverse = try self.name(&r, wideLength: true, maxChars: 255)
                result.append(RelationInfo(name: name, inverseName: inverse,
                                           sourceField: fieldNames[src] ?? src,
                                           destinationField: fieldNames[dst] ?? dst))
            } catch {
                warnings.append("relation #\(entry.index + 1): \(error)")
            }
            return true
        }
        return result
    }

    /// Counts records by resource type in a resource table (each record starts
    /// with its 4-char type code as an integer).
    ///
    /// Record block ("rec1"): 28-byte header, i32 field count, then field data.
    func resourceSummary(of table: DataTable, options: AnalysisOptions) throws -> ResourceSummary {
        var counts: [String: Int] = [:]
        var scanned = 0
        let deadline = Date().addingTimeInterval(options.timeBudget)
        let finished = try walkAddressTable(at: table.recordTableAddress) { entry, header in
            if scanned >= options.maxRecordsToScan || Date() > deadline { return false }
            guard header.tag == "rec1", let d = try? source.read(at: entry.address + 32, length: 4) else { return true }
            let bytes = [UInt8](d)
            counts[Self.fourCharCode(littleEndian ? bytes.reversed() : bytes), default: 0] += 1
            scanned += 1
            return true
        }
        let types = counts.map { ResourceTypeCount(type: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.type < $1.type }
        return ResourceSummary(total: table.recordCount, scanned: scanned,
                               complete: finished && scanned >= table.recordCount, types: types)
    }

    static func fourCharCode(_ b: [UInt8]) -> String {
        if b.allSatisfy({ (0x20...0x7E).contains($0) }) { return String(decoding: b, as: UTF8.self) }
        return "0x" + b.map { String(format: "%02X", $0) }.joined()
    }
}
