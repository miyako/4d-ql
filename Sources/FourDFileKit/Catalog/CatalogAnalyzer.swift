import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum CatalogError: Error, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self { case .invalid(let message): return "invalid 4D catalog: \(message)" }
    }
}

public struct CatalogAnalyzer: FileAnalyzer {
    public init() {}
    public var identifier: String { "4dcatalog" }
    public var contentTypes: [String] { ["com.4d.4d.catalog"] }
    public var filenameExtensions: [String] { ["4dcatalog"] }

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        guard source.size <= 32 * 1024 * 1024 else {
            throw CatalogError.invalid("XML exceeds the 32 MiB catalog size limit")
        }
        let data = try source.read(at: 0, length: Int(source.size))
        if XMLParser.declaresUnreportedEntities(data) { throw CatalogError.invalid("custom XML entities are not supported") }
        let parser = XMLParser(data: data)
        let document = CatalogDocument()
        parser.delegate = document
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        let parsed = parser.parseStrictly()
        if let failure = document.failure { throw CatalogError.invalid(failure) }
        guard parsed else {
            throw CatalogError.invalid("XML at line \(parser.lineNumber), column \(parser.columnNumber): \(parser.parserError?.localizedDescription ?? "parse failed")")
        }
        guard let root = document.root, root.name == "base" else {
            throw CatalogError.invalid("expected a <base> root element")
        }
        return try CatalogDecoder().decode(root, source: source)
    }
}

private final class CatalogNode {
    let name: String
    let attributes: [String: String]
    var children: [CatalogNode] = []

    init(_ name: String, _ attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    subscript(_ key: String) -> String? { attributes[key] }
    func child(_ name: String) -> CatalogNode? { children.first { $0.name == name } }
    func all(_ name: String) -> [CatalogNode] { children.filter { $0.name == name } }
}

private final class CatalogDocument: NSObject, XMLParserDelegate {
    var root: CatalogNode?
    var failure: String?
    private var stack: [CatalogNode] = []
    private var elementCount = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard failure == nil else { return }
        elementCount += 1
        guard elementCount <= 200_000, stack.count < 128 else {
            failure = "XML exceeds the element or nesting limit"
            parser.stopFromDelegate()
            return
        }
        let node = CatalogNode(elementName, attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        failure = "custom XML entities are not supported"
        parser.stopFromDelegate()
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        failure = "external XML entities are not supported"
        parser.stopFromDelegate()
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        failure = "external XML entities are not supported"
        parser.stopFromDelegate()
        return nil
    }
}

private final class CatalogDecoder {
    private var warnings: [String] = []

    func decode(_ root: CatalogNode, source: ByteSource) throws -> CatalogInfo {
        let tables = root.all("table").compactMap(table)
        let tableLookup = CatalogLookup(tables.map { ($0.uuid, $0.name) })
        let fieldLookups = tables.map { CatalogLookup($0.fields.map { ($0.uuid, $0.name) }) }
        var relations: [CatalogRelation] = []
        for node in root.all("relation") {
            guard let sourceEndpoint = endpoint(node, kind: "source", tables: tables, tableLookup: tableLookup, fieldLookups: fieldLookups),
                  let destination = endpoint(node, kind: "destination", tables: tables, tableLookup: tableLookup, fieldLookups: fieldLookups) else {
                warn("Skipped a relation with missing source or destination references.")
                continue
            }
            relations.append(CatalogRelation(
                uuid: node["uuid"] ?? "", name: node["name_Nto1"] ?? "", inverseName: node["name_1toN"] ?? "",
                source: sourceEndpoint, destination: destination,
                autoLoadManyToOne: boolean(node, "auto_load_Nto1"),
                autoLoadOneToMany: boolean(node, "auto_load_1toN"),
                foreignKey: boolean(node, "foreign_key"), integrity: node["integrity"]))
        }
        return CatalogInfo(fileName: source.url.lastPathComponent, fileSize: source.size,
                           name: root["name"] ?? "", databaseUUID: root["uuid"] ?? "",
                           collationLocale: root["collation_locale"], schemas: root.all("schema").compactMap { $0["name"] },
                           tables: tables, relations: relations, indexCount: root.all("index").count, warnings: warnings)
    }

    private func table(_ node: CatalogNode) -> CatalogTable? {
        guard let name = node["name"], !name.isEmpty else {
            warn("Skipped a table without a name.")
            return nil
        }
        var fields = node.all("field").compactMap { field($0, tableName: name) }
        let lookup = CatalogLookup(fields.map { ($0.uuid, $0.name) })
        for key in node.all("primary_key") {
            if let index = lookup.match(uuid: key["field_uuid"], name: key["field_name"]) {
                fields[index].primaryKey = true
            } else { warn("Unresolved primary key in table \(name).") }
        }
        let extra = node.child("table_extra")
        var position: CatalogPosition?
        if let coordinates = extra?.child("editor_table_info")?.child("coordinates") {
            if let x = coordinates["left"].flatMap(Double.init), x.isFinite,
               let y = coordinates["top"].flatMap(Double.init), y.isFinite {
                position = CatalogPosition(x: x, y: y)
            } else { warn("Ignored invalid editor coordinates for table \(name).") }
        }
        return CatalogTable(number: integer(node, "id"), name: name, uuid: node["uuid"] ?? "", fields: fields,
                            encryptable: boolean(node, "encryptable"), hidden: extra.map { !boolean($0, "visible", default: true) } ?? false,
                            position: position)
    }

    private func field(_ node: CatalogNode, tableName: String) -> CatalogField? {
        guard let name = node["name"], !name.isEmpty else {
            warn("Skipped a field without a name in table \(tableName).")
            return nil
        }
        let type = integer(node, "type")
        if type == nil { warn("Unknown field type for [\(tableName)]\(name).") }
        let length = integer(node, "limiting_length")
        if let length, length < 0 { warn("Ignored negative limiting length for [\(tableName)]\(name).") }
        return CatalogField(number: integer(node, "id"), name: name, uuid: node["uuid"] ?? "",
                            typeCode: type ?? -1, limitingLength: length.flatMap { $0 > 0 ? $0 : nil },
                            unique: boolean(node, "unique"), autoSequence: boolean(node, "autosequence"),
                            notNull: boolean(node, "not_null") || boolean(node, "never_null"),
                            hidden: node.child("field_extra").map { !boolean($0, "visible", default: true) } ?? false,
                            primaryKey: false, indexUUIDs: node.all("index_ref").compactMap { $0["uuid"] })
    }

    private func endpoint(_ relation: CatalogNode, kind: String, tables: [CatalogTable],
                          tableLookup: CatalogLookup, fieldLookups: [CatalogLookup]) -> CatalogEndpoint? {
        guard let related = relation.all("related_field").first(where: { $0["kind"] == kind }),
              let field = related.child("field_ref"), let table = field.child("table_ref") else { return nil }
        var result = CatalogEndpoint(tableName: table["name"] ?? "", tableUUID: table["uuid"] ?? "",
                                     fieldName: field["name"] ?? "", fieldUUID: field["uuid"] ?? "")
        result.tableIndex = tableLookup.match(uuid: table["uuid"], name: table["name"])
        if let ti = result.tableIndex {
            result.tableName = tables[ti].name
            result.fieldIndex = fieldLookups[ti].match(uuid: field["uuid"], name: field["name"])
            if let fi = result.fieldIndex { result.fieldName = tables[ti].fields[fi].name }
        }
        if result.tableIndex == nil || result.fieldIndex == nil {
            warn("Unresolved relation \(kind): \(result.label).")
        }
        return result
    }

    private func integer(_ node: CatalogNode, _ key: String) -> Int? {
        guard let raw = node[key] else { return nil }
        let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if value == nil { warn("Invalid \(key) attribute on <\(node.name)>.") }
        return value
    }

    private struct CatalogLookup {
        private var uuids: [String: [Int]] = [:]
        private var names: [String: [Int]] = [:]

        init(_ identities: [(uuid: String, name: String)]) {
            for (index, identity) in identities.enumerated() {
                if !identity.uuid.isEmpty { uuids[Self.normalize(identity.uuid), default: []].append(index) }
                if !identity.name.isEmpty { names[identity.name, default: []].append(index) }
            }
        }

        func match(uuid: String?, name: String?) -> Int? {
            if let uuid, !uuid.isEmpty, let matches = uuids[Self.normalize(uuid)] {
                return matches.count == 1 ? matches[0] : nil
            }
            guard let name, let matches = names[name], matches.count == 1 else { return nil }
            return matches[0]
        }

        private static func normalize(_ uuid: String) -> String {
            uuid.replacingOccurrences(of: "-", with: "").uppercased()
        }
    }

    private func boolean(_ node: CatalogNode, _ key: String, default defaultValue: Bool = false) -> Bool {
        guard let raw = node[key] else { return defaultValue }
        switch raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: warn("Invalid \(key) attribute on <\(node.name)>."); return defaultValue
        }
    }

    private func warn(_ message: String) {
        // Keep diagnostics bounded even when an export has thousands of bad attributes.
        if warnings.count < 100 { warnings.append(message) }
        else if warnings.count == 100 { warnings.append("Further catalog warnings omitted.") }
    }
}
