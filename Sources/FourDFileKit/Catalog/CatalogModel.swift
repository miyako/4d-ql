import Foundation

public struct CatalogPosition: Codable {
    public var x: Double
    public var y: Double
}

public struct CatalogField: Codable {
    public var number: Int?
    public var name: String
    public var uuid: String
    public var typeCode: Int
    public var limitingLength: Int?
    public var unique: Bool
    public var autoSequence: Bool
    public var notNull: Bool
    public var hidden: Bool
    public var primaryKey: Bool
    public var indexUUIDs: [String]

    public var kind: FieldKind? { FieldKind(rawValue: typeCode) }
    public var typeName: String { FieldInfo.typeName(code: typeCode, limitingLength: limitingLength) }
}

public struct CatalogTable: Codable {
    public var number: Int?
    public var name: String
    public var uuid: String
    public var fields: [CatalogField]
    public var encryptable: Bool
    public var hidden: Bool
    public var position: CatalogPosition?
}

public struct CatalogEndpoint: Codable {
    public var tableName: String
    public var tableUUID: String
    public var fieldName: String
    public var fieldUUID: String
    /// Resolved array offsets, independent of table/field IDs and XML order.
    public var tableIndex: Int?
    public var fieldIndex: Int?

    public var label: String { "[\(tableName)]\(fieldName)" }
}

public struct CatalogRelation: Codable {
    public var uuid: String
    public var name: String
    public var inverseName: String
    public var source: CatalogEndpoint
    public var destination: CatalogEndpoint
    public var autoLoadManyToOne: Bool
    public var autoLoadOneToMany: Bool
    public var foreignKey: Bool
    public var integrity: String?
}

public struct CatalogInfo: AnalysisModel {
    public var kind: String { "catalog.structure" }
    public var fileName: String
    public var fileSize: Int64
    public var name: String
    public var databaseUUID: String
    public var collationLocale: String?
    public var schemas: [String]
    public var tables: [CatalogTable]
    public var relations: [CatalogRelation]
    public var indexCount: Int
    public var warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case kind, fileName, fileSize, name, databaseUUID, collationLocale, schemas, tables, relations, indexCount, warnings
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(fileSize, forKey: .fileSize)
        try c.encode(name, forKey: .name)
        try c.encode(databaseUUID, forKey: .databaseUUID)
        try c.encodeIfPresent(collationLocale, forKey: .collationLocale)
        try c.encode(schemas, forKey: .schemas)
        try c.encode(tables, forKey: .tables)
        try c.encode(relations, forKey: .relations)
        try c.encode(indexCount, forKey: .indexCount)
        try c.encode(warnings, forKey: .warnings)
    }
}
