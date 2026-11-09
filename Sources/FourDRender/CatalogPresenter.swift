import Foundation
import FourDFileKit

public struct CatalogPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["catalog.structure"] }
    static let maxDiagramFields = 8

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? CatalogInfo else { return nil }
        let fields = info.tables.flatMap(\.fields)
        var report = Report(title: info.fileName, subtitle: "4D catalog (XML)" + (info.name.isEmpty ? "" : " · \(info.name)"))
        report.sections.append(Section("Structure diagram", info.tables.isEmpty ? [.text("No tables.")] : [.structureDiagram(diagram(info))]))
        var database: [Block] = []
        if !info.databaseUUID.isEmpty {
            database.append(.identity(label: "Database UUID", value: info.databaseUUID,
                                      caption: "Data files created for this catalog carry the same UUID."))
        }
        var properties = [KeyValue("Tables", Fmt.n(info.tables.count)), KeyValue("Fields", Fmt.n(fields.count)),
                          KeyValue("Relations", Fmt.n(info.relations.count)), KeyValue("Indexes", Fmt.n(info.indexCount)),
                          KeyValue("Format", "XML"), KeyValue("File size", Fmt.bytes(info.fileSize))]
        if let locale = info.collationLocale {
            properties.append(KeyValue("Sort/search language", Locale.current.localizedString(forIdentifier: locale) ?? locale))
        }
        if !info.schemas.isEmpty {
            properties.append(KeyValue("Schemas", info.schemas.prefix(8).joined(separator: ", ") +
                                       (info.schemas.count > 8 ? " and \(info.schemas.count - 8) more" : "")))
        }
        database.append(.keyValues(properties))
        let encryptable = info.tables.filter(\.encryptable)
        if !encryptable.isEmpty {
            database += [
                .keyValues([KeyValue("Encryptable tables", encryptable.prefix(8).map(\.name).joined(separator: ", ") +
                                     (encryptable.count > 8 ? " and \(encryptable.count - 8) more" : ""))]),
                .note("The catalog marks tables as encryptable; it does not reveal whether a data file is encrypted.", .neutral),
            ]
        }
        report.sections.append(Section("Details", [.disclosure(summary: "Catalog details", detail: nil, blocks: database)]))
        if !info.warnings.isEmpty {
            report.sections.append(Section("Parser notes", info.warnings.prefix(5).map { .note($0, .warning) } +
                                           (info.warnings.count > 5 ? [.note("Further diagnostics are available in fourdql --json.", .neutral)] : [])))
        }
        return report
    }

    private func diagram(_ info: CatalogInfo) -> StructureDiagram {
        let shown = info.tables
        let relations = info.relations.filter {
            guard let source = $0.source.tableIndex, let destination = $0.destination.tableIndex else { return false }
            return shown.indices.contains(source) && shown.indices.contains(destination)
                && $0.source.fieldIndex != nil && $0.destination.fieldIndex != nil
        }
        var connected: [Int: Set<Int>] = [:]
        for relation in relations {
            for endpoint in [relation.source, relation.destination] {
                if let table = endpoint.tableIndex, let field = endpoint.fieldIndex { connected[table, default: []].insert(field) }
            }
        }
        let nodes = shown.enumerated().map { ti, table -> DiagramNode in
            // Keep keys and joins visible before filling the remaining rows.
            let priority = table.fields.indices.sorted {
                let a = table.fields[$0].primaryKey || (connected[ti]?.contains($0) ?? false)
                let b = table.fields[$1].primaryKey || (connected[ti]?.contains($1) ?? false)
                return a != b ? a : $0 < $1
            }
            let selected = priority.prefix(Self.maxDiagramFields).sorted()
            let fields = selected.map { fi in
                let field = table.fields[fi]
                return DiagramField(id: "\(fi)", name: field.name, type: field.typeName, primaryKey: field.primaryKey,
                                    hidden: field.hidden, indexed: !field.indexUUIDs.isEmpty, icon: icon(for: field.kind))
            }
            return DiagramNode(id: "\(ti)", title: table.name, fields: fields,
                               position: table.position.map { DiagramPosition(x: $0.x, y: $0.y) },
                               omittedFields: table.fields.count - fields.count, hidden: table.hidden)
        }
        let edges = relations.compactMap { relation -> DiagramEdge? in
            guard let st = relation.source.tableIndex, let sf = relation.source.fieldIndex,
                  let dt = relation.destination.tableIndex, let df = relation.destination.fieldIndex else { return nil }
            var label = "\(relation.source.label) → \(relation.destination.label)"
            let names = [relation.name, relation.inverseName].filter { !$0.isEmpty }.joined(separator: " / ")
            if !names.isEmpty { label += " · \(names)" }
            if let integrity = relation.integrity { label += " · integrity: \(integrity)" }
            label += " · auto-load N→1: \(relation.autoLoadManyToOne ? "on" : "off"), 1→N: \(relation.autoLoadOneToMany ? "on" : "off")"
            if relation.foreignKey { label += " · foreign key" }
            return DiagramEdge(sourceNode: "\(st)", sourceField: "\(sf)", destinationNode: "\(dt)", destinationField: "\(df)", label: label)
        }
        return StructureDiagram(nodes: nodes, edges: edges, omittedTables: info.tables.count - nodes.count,
                                omittedRelations: info.relations.count - edges.count)
    }

    private func icon(for kind: FieldKind?) -> DiagramField.Icon {
        switch kind {
        case .boolean: return .boolean
        case .byte, .integer, .longint, .integer64: return .integer
        case .real, .float: return .real
        case .text, .legacyText, .unlimitedText: return .text
        case .date: return .date
        case .time: return .time
        case .picture: return .picture
        case .uuid: return .uuid
        case .blob, .legacyBlob: return .blob
        case .object: return .object
        case nil: return .unknown
        }
    }
}
