import Foundation

// Typed models for files in the DB4D container format (.4DD data files and
// binary .4DB structure files). Field names describe what the bytes mean; the
// offsets they come from are documented in DB4DHeader.swift and DB4DCatalog.swift.

/// Block timestamp as stored by 4D (milliseconds since midnight, day, month, year).
/// The time zone is not recorded, so it is kept as local wall-clock components.
public struct DB4DTimestamp: Codable, Equatable, Comparable {
    public var year: Int, month: Int, day: Int, milliseconds: Int

    public var isValid: Bool {
        (1990...2200).contains(year) && (1...12).contains(month) && (1...31).contains(day) && (0..<86_400_000).contains(milliseconds)
    }

    /// "2026-03-25 08:38:49"
    public var text: String {
        let s = milliseconds / 1000
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", year, month, day, s / 3600, s / 60 % 60, s % 60)
    }

    public static func < (a: Self, b: Self) -> Bool {
        (a.year, a.month, a.day, a.milliseconds) < (b.year, b.month, b.day, b.milliseconds)
    }
}

public struct DB4DHeader: Codable {
    public var littleEndian: Bool
    /// 0 = cache flushed correctly, -1 = flush interrupted.
    public var lastOperation: Int32
    public var segmentCount: Int
    public var formatVersion: String
    /// Shared by a structure file and the data files created for it.
    public var databaseUUID: String
    public var logicalEOF: Int64
    public var blockSize: Int
    public var headerModificationCount: Int
    public var lastJournalAction: Int64
    public var journalFileCount: Int
    public var dataTableCount: Int
    public var needsRepair: Bool
    public var indexesInSeparateFile: Bool
    public var tableDefinitionCount: Int
    public var relationCount: Int
    public var sequenceCount: Int
    public var indexCount: Int
    public var structureIndexCount: Int
    public var flushCount: Int
    /// Windows LCID of the sort/search language, or -4444 for "system".
    public var dialectCode: Int32
    public var dialectLocaleIdentifier: String?
    public var collation: CollationOptions

    public var flushedCleanly: Bool { lastOperation == 0 }
}

public struct CollationOptions: Codable {
    public var raw: UInt8
    public var useICU: Bool
    public var ignoreWildcardInMiddle: Bool
    public var secondaryStrengthForMatching: Bool
    public var quaternaryStrengthForSorting: Bool
    public var hiraganaFirstOnQuaternaryLevel: Bool
    public var languageNeutralDeadchar: Bool
    public var traditionalStyleSorting: Bool

    init(_ b: UInt8) {
        raw = b
        useICU = b & 1 != 0
        ignoreWildcardInMiddle = b & 2 != 0
        secondaryStrengthForMatching = b & 4 != 0
        quaternaryStrengthForSorting = b & 8 != 0
        hiraganaFirstOnQuaternaryLevel = b & 16 != 0
        languageNeutralDeadchar = b & 32 != 0
        traditionalStyleSorting = b & 64 != 0
    }
}

/// 4D field types, numbered as in the `type` attribute of catalog.4DCatalog.
public enum FieldKind: Int, Codable {
    case boolean = 1, integer = 3, longint = 4, integer64 = 5, real = 6, float = 7
    case date = 8, time = 9, text = 10, picture = 12, uuid = 13, legacyText = 14, blob = 18, object = 21
}

public struct FieldInfo: Codable {
    public var number: Int
    public var name: String
    public var uuid: String
    public var typeCode: Int
    /// Alpha fields have a limiting length; Text fields (same type code) do not.
    public var limitingLength: Int?

    public var kind: FieldKind? { FieldKind(rawValue: typeCode) }

    public var typeName: String {
        switch kind {
        case .boolean: return "Boolean"
        case .integer: return "Integer"
        case .longint: return "Long Integer"
        case .integer64: return "Integer 64 bit"
        case .real: return "Real"
        case .float: return "Float"
        case .date: return "Date"
        case .time: return "Time"
        case .text: if let n = limitingLength { return "Alpha (\(n))" } else { return "Text" }
        case .picture: return "Picture"
        case .uuid: return "UUID"
        case .legacyText: return "Text"
        case .blob: return "BLOB"
        case .object: return "Object"
        case nil: return "Type \(typeCode)"
        }
    }
}

public struct TableInfo: Codable {
    public var number: Int
    public var name: String
    public var uuid: String
    public var fields: [FieldInfo]
    /// Present for tables that have storage in this file (always for .4DD tables).
    public var recordCount: Int?
    public var blobCount: Int?
    public var lastModified: DB4DTimestamp?
    /// Number of older definitions of the same table kept in the file.
    public var historicalDefinitions: Int
}

public struct RelationInfo: Codable {
    public var name: String
    public var inverseName: String
    public var sourceField: String
    public var destinationField: String
}

public struct ExtraProperty: Codable {
    public var key: String
    public var value: String
}

public struct ResourceTypeCount: Codable {
    public var type: String
    public var count: Int
}

/// A resource-table summary (binary structure files store forms, menus,
/// pictures, etc. as typed resources).
public struct ResourceSummary: Codable {
    public var total: Int
    public var scanned: Int
    public var complete: Bool
    public var types: [ResourceTypeCount]
}

/// Everything known about a DB4D container file.
public struct DB4DFileInfo: AnalysisModel {
    public enum Role: String, Codable { case data, structure }

    public var kind: String { role == .data ? "db4d.data" : "db4d.structure" }
    public var role: Role
    public var fileName: String
    public var fileSize: Int64
    public var header: DB4DHeader
    public var tables: [TableInfo]
    public var relations: [RelationInfo]
    public var extraProperties: [ExtraProperty]
    public var resources: ResourceSummary?
    public var lastModified: DB4DTimestamp?
    /// Non-fatal problems met while parsing; the preview still shows what was read.
    public var warnings: [String]

    public var totalRecords: Int { tables.reduce(0) { $0 + ($1.recordCount ?? 0) } }

    private enum CodingKeys: String, CodingKey {
        case kind, role, fileName, fileSize, header, tables, relations, extraProperties, resources, lastModified, warnings
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(role, forKey: .role)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(fileSize, forKey: .fileSize)
        try c.encode(header, forKey: .header)
        try c.encode(tables, forKey: .tables)
        try c.encode(relations, forKey: .relations)
        try c.encode(extraProperties, forKey: .extraProperties)
        try c.encodeIfPresent(resources, forKey: .resources)
        try c.encodeIfPresent(lastModified, forKey: .lastModified)
        try c.encode(warnings, forKey: .warnings)
    }
}
